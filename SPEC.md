---
eip: XXXX
title: Function-Scoped Delegated Authorization Registry
description: A registry primitive for granting operators narrowly-scoped, per-function authorization over an owner's positions without custody transfer.
author: Ocean Vael
discussions-to: (TBD)
status: Draft
type: Standards Track
category: ERC
created: 2026-05-04
requires: 712
---

## Abstract

This ERC defines a registry-based authorization primitive that allows an owner to grant an operator the right to call a specific function on a specific contract — and nothing more. Permissions are identified by a four-element key `(owner, operator, target, selector)` and stored as `uint48` expiry timestamps, making time-bounded grants a first-class feature. An EIP-712 signed permit enables gasless delegation without a prior on-chain transaction from the owner. Integrating contracts adopt the standard by calling a single view function on the registry inside a modifier.

## Motivation

DeFi protocols increasingly want to support automation, social trading, and intent-based execution — all of which require some form of delegation. Existing mechanisms fail in different ways:

**Token approvals** are scoped to a contract but not to a function. Approving a vault or manager to act on a user's behalf implicitly grants that contract broad authority over the approved asset.

**Custody vaults** require users to transfer assets into a contract under the vault's control. Non-custodial feature sets become architecturally difficult, and users bear smart contract risk they may not understand.

**Bespoke per-protocol authorization** solves the problem for a single protocol but is not composable: wallets cannot render a unified view of what a user has delegated across applications, and operators must integrate separately with every protocol they interact with.

What is missing is a standard, selector-scoped permission primitive: one that any contract can integrate with a single line of code, that wallets can index and display uniformly, and that covers the common delegation patterns — automation, compounding bots, social copying — without requiring custody transfer. This ERC defines that primitive.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Definitions

- **Owner** — the address whose account, position, or assets the permission governs.
- **Operator** — the address being authorized to act on the owner's behalf.
- **Target** — the contract on which the operator is authorized to call a function.
- **Selector** — the four-byte ABI function selector (`bytes4`) of the specific function the operator may call.
- **Permission key** — the four-element tuple `(owner, operator, target, selector)`.
- **Expiry** — a `uint48` Unix timestamp. `0` means the permission is not set or has been revoked; `type(uint48).max` means the permission never expires.

### Interface

A compliant registry MUST implement the following interface:

```solidity
interface IPermissionRegistry {

    struct PermissionKey {
        address owner;
        address operator;
        address target;
        bytes4 selector;
    }

    struct PermissionEntry {
        PermissionKey key;
        uint48 expiry;
    }

    struct PermissionPermit {
        address owner;
        address operator;
        address target;
        bytes4 selector;
        uint48 expiry;
        uint256 nonce;
        uint256 deadline;
    }

    error PermissionDenied(address owner, address operator, address target, bytes4 selector);
    error PermissionExpired(address owner, address operator, address target, bytes4 selector);
    error InvalidAddress();
    error InvalidSelector();
    error InvalidExpiry();
    error InvalidSignature();
    error DeadlineExpired();
    error InvalidNonce(uint256 expected, uint256 actual);

    event PermissionSet(
        address indexed owner,
        address indexed operator,
        address indexed target,
        bytes4 selector,
        bool approved,
        uint48 expiry
    );

    function grant(address operator, address target, bytes4 selector) external;
    function grantWithExpiry(address operator, address target, bytes4 selector, uint48 expiry) external;
    function revoke(address operator, address target, bytes4 selector) external;
    function grantBatch(PermissionKey[] calldata keys) external;
    function grantBatchWithExpiry(PermissionEntry[] calldata entries) external;
    function revokeBatch(PermissionKey[] calldata keys) external;

    function permitPermission(PermissionPermit calldata permit, bytes calldata signature) external;

    function isAuthorizedCall(address owner, address operator, address target, bytes4 selector)
        external view returns (bool);
    function requireAuthorizedCall(address owner, address operator, address target, bytes4 selector)
        external view;
    function permissionExpiry(address owner, address operator, address target, bytes4 selector)
        external view returns (uint48);

    function permissionNonce(address owner) external view returns (uint256);
}
```

### Permission Storage

The registry MUST store each permission as a `uint48` expiry value keyed by `(owner, operator, target, selector)`. The encoding is:

| Stored value | Meaning |
|---|---|
| `0` | Permission not set or revoked |
| `type(uint48).max` | Permanent permission (never expires) |
| Any other value | Permission expires at that Unix timestamp |

### Grant and Revoke Functions

**`grant(address operator, address target, bytes4 selector)`**

MUST set the permission for `(msg.sender, operator, target, selector)` to `type(uint48).max`. MUST revert with `InvalidAddress` if any address argument is `address(0)`. MUST revert with `InvalidSelector` if `selector` is `bytes4(0)`. MUST emit `PermissionSet`.

**`grantWithExpiry(address operator, address target, bytes4 selector, uint48 expiry)`**

MUST set the permission for `(msg.sender, operator, target, selector)` to `expiry`. MUST revert with `InvalidExpiry` if `expiry == 0` or `expiry <= block.timestamp`. MUST revert with `InvalidAddress` or `InvalidSelector` under the same conditions as `grant`. MUST emit `PermissionSet`.

**`revoke(address operator, address target, bytes4 selector)`**

MUST set the permission for `(msg.sender, operator, target, selector)` to `0`. MUST NOT revert if the permission was not previously set. MUST emit `PermissionSet`.

**`grantBatch(PermissionKey[] calldata keys)`**

For each key in `keys`: MUST revert with `PermissionDenied` if `key.owner != msg.sender`. Otherwise MUST behave as `grant` for that key. The operation MUST be atomic — if any key causes a revert, no permissions are written.

**`grantBatchWithExpiry(PermissionEntry[] calldata entries)`**

For each entry: MUST revert with `PermissionDenied` if `entry.key.owner != msg.sender`. MUST revert with `InvalidExpiry` if `entry.expiry == 0` or `entry.expiry <= block.timestamp`. Otherwise MUST behave as `grantWithExpiry`. MUST be atomic.

**`revokeBatch(PermissionKey[] calldata keys)`**

For each key: MUST revert with `PermissionDenied` if `key.owner != msg.sender`. Otherwise MUST behave as `revoke`. MUST be atomic.

### Authorization Queries

**`isAuthorizedCall(address owner, address operator, address target, bytes4 selector) → bool`**

MUST return `true` if and only if the stored expiry `e` for the key satisfies `e != 0 && block.timestamp <= e`. MUST NOT revert.

**`requireAuthorizedCall(address owner, address operator, address target, bytes4 selector)`**

MUST revert with `PermissionDenied` if the stored expiry is `0`. MUST revert with `PermissionExpired` if the stored expiry is nonzero but `block.timestamp > expiry`. MUST return without reverting if the permission is valid. The distinction between `PermissionDenied` and `PermissionExpired` is REQUIRED so callers can differentiate between a permission that was never granted and one that has lapsed.

**`permissionExpiry(address owner, address operator, address target, bytes4 selector) → uint48`**

MUST return the raw stored value for the given key without any interpretation. A return value of `0` means not set or revoked; `type(uint48).max` means permanent.

### The PermissionSet Event

A `PermissionSet` event MUST be emitted on every call to `grant`, `grantWithExpiry`, `revoke`, `grantBatch`, `grantBatchWithExpiry`, `revokeBatch`, and `permitPermission` that modifies state. The `approved` field MUST be `true` if the resulting expiry is nonzero, and `false` if it is `0`. The `expiry` field MUST reflect the value written to storage.

Indexers can reconstruct the complete set of active permissions and their expiries from `PermissionSet` events alone, without querying contract state.

### Gasless Permit

**`permitPermission(PermissionPermit calldata permit, bytes calldata signature)`**

Allows an owner to authorize or revoke a permission by submitting an EIP-712 signed message, without executing a transaction themselves.

A call to `permitPermission` MUST:

1. Revert with `DeadlineExpired` if `block.timestamp > permit.deadline`.
2. Revert with `InvalidExpiry` if `permit.expiry != 0 && permit.expiry <= block.timestamp`.
3. Revert with `InvalidNonce(current, permit.nonce)` if `permit.nonce` does not equal `permissionNonce[permit.owner]`.
4. Revert with `InvalidSignature` if the recovered signer of the EIP-712 digest (defined below) is not `permit.owner`.
5. On success: increment `permissionNonce[permit.owner]` by 1, write `permit.expiry` to the permission slot for `(permit.owner, permit.operator, permit.target, permit.selector)`, and emit `PermissionSet`.

The EIP-712 typed data structure is:

```
PermissionPermit(
    address owner,
    address operator,
    address target,
    bytes4 selector,
    uint48 expiry,
    uint256 nonce,
    uint256 deadline
)
```

The struct hash is:

```
keccak256(abi.encode(
    keccak256("PermissionPermit(address owner,address operator,address target,bytes4 selector,uint48 expiry,uint256 nonce,uint256 deadline)"),
    permit.owner,
    permit.operator,
    permit.target,
    permit.selector,
    permit.expiry,
    permit.nonce,
    permit.deadline
))
```

The digest signed by the owner is:

```
keccak256(abi.encodePacked(
    hex"1901",
    DOMAIN_SEPARATOR,
    structHash
))
```

where `DOMAIN_SEPARATOR` is the EIP-712 domain separator with `name = "PermissionRegistry"` and `version = "1"`.

The `expiry` field in `PermissionPermit` follows the same encoding as a direct grant: `0` means revoke, `type(uint48).max` means permanent. A single signed permit can therefore express a temporary delegation, a permanent delegation, or a gasless revocation.

The `signature` MUST be a 65-byte `secp256k1` signature in the format `r ++ s ++ v`. High-s signatures MUST be rejected.

**`permissionNonce(address owner) → uint256`**

MUST return the current nonce for `owner`. This value is incremented after each successful `permitPermission` call for that owner.

### Recommended Integration Pattern

Integrating contracts SHOULD inherit or re-implement the following modifier pattern:

```solidity
IPermissionRegistry public immutable registry;

modifier onlyAuthorized(address owner) {
    if (msg.sender != owner) {
        registry.requireAuthorizedCall(owner, msg.sender, address(this), msg.sig);
    }
    _;
}
```

The owner always retains direct access (`msg.sender == owner` bypasses the registry check). Any other caller must hold a valid permission for the calling function's selector on this contract. The `msg.sig` value is the four-byte selector of the currently-executing function, so no additional bookkeeping is required to scope the check to the correct function.

Each function on the target contract that should be independently delegatable MUST apply this modifier separately. Functions applied with the same modifier call are independently grantable — granting permission for one does not affect authorization for any other.

## Rationale

### Four-element key

The key `(owner, operator, target, selector)` is the minimal set of dimensions needed to express the primitive without ambiguity. Omitting `owner` would require a separate registry per user or per contract. Omitting `target` would require the registry to somehow know which contract is being called. Omitting `selector` reduces the primitive to a contract-level approval, which is not much better than an ERC-20 approval. Adding further dimensions (e.g. parameter constraints, chain ID) would require integrators to commit to a parameter encoding scheme at the standard level, which is premature.

### uint48 expiry rather than bool plus a separate expiry mapping

Storing a single `uint48` per key encodes three states — not set, permanent, and time-bounded — without a second mapping or a packed struct. `uint48` is sufficient for any plausible timestamp (it covers dates through year 891,000). The encoding makes every read a single `SLOAD` and keeps the implementation easy to audit. An alternative of `bool approved` plus `uint48 expiry` in a packed struct was considered but rejected on the grounds that the two fields are not independently meaningful.

### Distinct PermissionDenied and PermissionExpired errors

Callers that receive `PermissionDenied` know they should prompt the user to grant access. Callers that receive `PermissionExpired` know the user previously delegated but the grant has lapsed — a meaningfully different UX state. Collapsing these into a single error would force callers to query `permissionExpiry` to distinguish them.

### Inclusive expiry boundary

A permission with `expiry == block.timestamp` is considered valid. This matches the convention used by EIP-2612's `deadline` parameter and avoids a one-second off-by-one at the boundary.

### Sequential per-owner nonces

Sequential nonces (rather than unordered / bitmap-style nonces as in Permit2) are simpler to reason about and to implement. The tradeoff is that two permits signed by the same owner for different operators have an implicit ordering dependency. For the expected use case — an owner signs a permit for a single operator, which is submitted before the next is needed — this is not a practical limitation.

### ExecutionPermit not included

An earlier draft included an `executeWithPermit` function: the owner signs specific calldata, a relayer submits, and the registry calls the target directly. This was removed because it turns the registry into an execution engine — a different category of primitive that introduces reentrancy surface and requires the registry to appear as `msg.sender` in the target. Any protocol that needs one-shot signed execution can call `permitPermission` and the target function in the same transaction, achieving the same effect without registry-level execution.

### No delegation chains

An operator cannot sub-delegate their permission to a third party. Delegation chains increase the difficulty of auditing what a given address can do and create revocation puzzles (revoking from A does not revoke from B if A already delegated to B). One-hop delegation is sufficient for all anticipated use cases.

## Backwards Compatibility

This ERC introduces a new registry contract and a new modifier pattern. It does not modify any existing standard and is fully additive. Existing ERC-20, ERC-721, and other token contracts are unaffected. Protocols that wish to adopt this standard for new contracts or wrappers can do so without any migration of existing state.

## Test Cases

The reference test suite at [`test/PermissionRegistry.t.sol`](./test/PermissionRegistry.t.sol) covers:

- Owner direct access (bypasses registry check)
- Granting and revoking single permissions
- Time-bounded grants: valid before expiry, expired after
- Expiry boundary condition (inclusive at `block.timestamp == expiry`)
- Overwriting a permanent grant with a time-bounded one and vice versa
- Batch grant atomicity: a single invalid key reverts the entire batch with no partial writes
- Permission key isolation: grants are scoped to `(owner, operator, target, selector)`; a stranger's `revoke` call cannot affect an owner's permission slot
- Operator isolation: an operator cannot revoke the permission granted to them by an owner
- Multiple owners granting to the same operator are independent
- `permitPermission`: correct grant and revoke, wrong signer, expired deadline, skipped nonce, replay rejection
- `permitPermission` with time-bounded expiry
- Permit-granted permissions are revocable via direct `revoke`
- High-s signature rejection
- Struct field mutation after signing invalidates the signature

## Reference Implementation

- Registry: [`src/PermissionRegistry.sol`](./src/PermissionRegistry.sol)
- Interface: [`src/interfaces/IPermissionRegistry.sol`](./src/interfaces/IPermissionRegistry.sol)
- Integration helper: [`src/base/PermissionedTarget.sol`](./src/base/PermissionedTarget.sol)
- EIP-712 utilities: [`src/utils/EIP712.sol`](./src/utils/EIP712.sol), [`src/utils/ECDSA.sol`](./src/utils/ECDSA.sol)
- Example integrations: [`src/examples/`](./src/examples/)

## Security Considerations

### Parameter constraints are the integrator's responsibility

This standard authorizes calls at the function-selector level. It does not constrain the arguments passed to the authorized function. A granted `rebalance()` permission does not prevent an operator from calling `rebalance()` with extreme or harmful parameters. Integrating contracts MUST implement any necessary parameter validation within the target function itself. Wrappers should be audited with this property explicitly in mind.

### One-hop delegation only

An operator cannot re-delegate their permission to another address. This is a deliberate design choice. Protocols that need multi-party delegation chains must implement that logic outside the registry.

### Immutable domain separator

The reference implementation computes the EIP-712 domain separator once at deployment using `block.chainid`. In the event of a chain split after deployment, the domain separator will remain valid on both forks, enabling cross-fork replay of signed permits. Production deployments SHOULD evaluate whether to recompute the domain separator dynamically on each signature verification.

### Revocation is not instant under mempool conditions

Because `grant` and `revoke` are ordinary transactions, a revocation submitted to the mempool does not take effect until it is mined. An operator aware of a pending revocation can front-run it by submitting an authorized call in the same block. Protocols with strict revocation requirements should consider time-delayed grants or additional application-layer controls.

### ecrecover returns address(0) on invalid input

The ECDSA implementation MUST verify that the recovered signer is not `address(0)`. The reference implementation does so. Implementations that call `ecrecover` directly without this check risk treating malformed signatures as valid grants from a zero-address owner.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE).

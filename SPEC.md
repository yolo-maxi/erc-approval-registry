---
eip: XXXX
title: Scoped Delegated Authorization Registry
description: A registry primitive for granting operators scoped authorization over a user's positions without custody transfer, supporting full-target approvals and selector bundles.
author: Ocean Vael, Francesco Renzi
discussions-to: (TBD)
status: Draft
type: Standards Track
category: ERC
created: 2026-05-04
requires: 712
---

## Abstract

This ERC defines a registry-based authorization primitive that allows a user to grant an operator the right to call functions on a specific target contract without transferring custody. Permissions are stored per `(user, operator, target)` as a compact authorization blob: either an expiry-only full-target approval, or an expiry followed by a sorted bundle of authorized function selectors. Time-bounded grants are first-class, and an EIP-712 signed permit enables gasless delegation without a prior on-chain transaction from the user. Integrating contracts adopt the standard by calling a single view function on the registry inside a modifier.

## Motivation

DeFi protocols increasingly want to support automation, social trading, and intent-based execution — all of which require some form of delegation. Existing mechanisms fail in different ways:

**Token approvals** are scoped to a contract but not to a function. Approving a vault or manager to act on a user's behalf implicitly grants that contract broad authority over the approved asset.

**Custody vaults** require users to transfer assets into a contract under the vault's control. Non-custodial feature sets become architecturally difficult, and users bear smart contract risk they may not understand.

**Bespoke per-protocol authorization** solves the problem for a single protocol but is not composable: wallets cannot render a unified view of what a user has delegated across applications, and operators must integrate separately with every protocol they interact with.

What is missing is a standard delegated-authorization primitive: one that any contract can integrate with a single line of code, that wallets can index and display uniformly, and that covers common delegation patterns — automation, forwarders, compounding bots, social copying — without requiring custody transfer. This ERC defines that primitive with two useful modes: cheap full-target approval for trusted forwarders, and selector-bundle approval for narrower delegation.

Human-readable signing is an important complementary concern, but it does not need to be solved entirely inside the primitive itself. A registry with a small, stable payload shape — `(user, operator, target, auth mode, selectors, expiry)` — is straightforward for wallets to render directly, while richer descriptions of delegated actions can be layered on through verified ABI metadata or descriptor standards such as ERC-7730. Wallets SHOULD clearly distinguish full-target approvals from selector-scoped approvals.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Definitions

- **User** — the address whose account, position, or assets the permission governs.
- **Operator** — the address being authorized to act on the user's behalf.
- **Target** — the contract on which the operator is authorized to call a function.
- **Selector** — the four-byte ABI function selector (`bytes4`) of a function the operator may call.
- **Selector bundle** — a sorted, unique list of `bytes4` selectors that share one expiry.
- **Full-target approval** — an approval for every selector on a target contract until the stored expiry.
- **Permission key** — the three-element tuple `(user, operator, target)` that maps to an authorization blob.
- **Expiry** — an externally-visible `uint48` Unix timestamp. `0` means the permission is not set or has been revoked; `type(uint48).max` means the permission never expires. Implementations MAY store this more compactly, for example as a `uint32` timestamp with `type(uint32).max` as the permanent sentinel.

### Interface

A compliant registry MUST implement the following interface:

```solidity
interface IPermissionRegistry {

    struct PermissionKey {
        address user;
        address operator;
        address target;
        bytes4 selector;
    }

    struct PermissionEntry {
        PermissionKey key;
        uint48 expiry;
    }

    struct PermissionPermit {
        address user;
        address operator;
        address target;
        bytes4 selector;
        uint48 expiry;
        uint256 nonce;
        uint256 deadline;
    }

    struct FullAuthorizationPermit {
        address user;
        address operator;
        address target;
        uint48 expiry;
        uint256 nonce;
        uint256 deadline;
    }

    error PermissionDenied(address user, address operator, address target, bytes4 selector);
    error PermissionExpired(address user, address operator, address target, bytes4 selector);
    error InvalidAddress();
    error InvalidSelector();
    error InvalidExpiry();
    error InvalidSignature();
    error DeadlineExpired();
    error InvalidNonce(uint256 expected, uint256 actual);

    event PermissionSet(
        address indexed user,
        address indexed operator,
        address indexed target,
        bytes4 selector,
        bool approved,
        uint48 expiry
    );

    event AuthorizationSet(
        address indexed user,
        address indexed operator,
        address indexed target,
        uint48 expiry,
        bytes4[] selectors
    );

    function grant(address operator, address target, bytes4 selector) external;
    function grantWithExpiry(address operator, address target, bytes4 selector, uint48 expiry) external;
    function revoke(address operator, address target, bytes4 selector) external;

    function grantFull(address operator, address target) external;
    function grantFullWithExpiry(address operator, address target, uint48 expiry) external;
    function revokeAll(address operator, address target) external;

    function grantSelectorBundle(address operator, address target, bytes4[] calldata selectors, uint48 expiry) external;

    function grantBatch(PermissionKey[] calldata keys) external;
    function grantBatchWithExpiry(PermissionEntry[] calldata entries) external;
    function revokeBatch(PermissionKey[] calldata keys) external;

    function permitPermission(PermissionPermit calldata permit, bytes calldata signature) external;
    function permitFullAuthorization(FullAuthorizationPermit calldata permit, bytes calldata signature) external;

    function isAuthorizedCall(address user, address operator, address target, bytes4 selector)
        external view returns (bool);
    function requireAuthorizedCall(address user, address operator, address target, bytes4 selector)
        external view;
    function permissionExpiry(address user, address operator, address target, bytes4 selector)
        external view returns (uint48);
    function rawPermissionData(address user, address operator, address target)
        external view returns (bytes memory);

    function permissionNonce(address user) external view returns (uint256);
}
```

### Permission Storage

The registry MUST expose authorization as a single authorization blob per `(user, operator, target)` permission key. The canonical encoding is:

```text
auth.length == 0: no approval
auth.length == 4: expiry only, meaning full-target approval
auth.length > 4: expiry followed by a selector bundle
```

The first four bytes encode the expiry. The reference implementation stores expiry as `uint32`, where:

- `0` means not set or revoked.
- `type(uint32).max` means permanent permission.
- Any other value means the permission expires at that Unix timestamp.

The externally-visible API continues to use `uint48` so the permanent sentinel remains `type(uint48).max`. Implementations that store a compact expiry MUST map external `type(uint48).max` to their internal permanent sentinel and MUST reject non-permanent expiries that cannot be represented by the storage encoding.

If the blob contains only the expiry, the operator is authorized for any selector on the target until the expiry. This mode is intended for trusted forwarders and other cases where the user wants to delegate the full target surface.

If the blob contains selectors, the remaining bytes MUST be a sequence of `bytes4` selectors. The selector list MUST be sorted in ascending order and MUST NOT contain duplicates. Implementations MUST reject malformed selector bundles.

### Grant and Revoke Functions

**`grant(address operator, address target, bytes4 selector)`**

MUST grant a permanent selector-scoped permission for `(msg.sender, operator, target, selector)`. MUST revert with `InvalidAddress` if any address argument is `address(0)`. MUST revert with `InvalidSelector` if `selector` is `bytes4(0)`. MUST emit `PermissionSet`.

If the current authorization blob for `(msg.sender, operator, target)` is an unexpired full-target approval, implementations SHOULD leave it unchanged because the selector is already authorized by the broader approval. A selector-scoped grant MUST NOT silently narrow, extend, or shorten an existing unexpired full-target approval. Otherwise, implementations MUST add `selector` to the selector bundle while preserving sorted uniqueness.

**`grantWithExpiry(address operator, address target, bytes4 selector, uint48 expiry)`**

MUST grant a selector-scoped permission until `expiry`. `type(uint48).max` MUST be treated as permanent. For finite expiries, the function MUST revert with `InvalidExpiry` if `expiry == 0`, `expiry <= block.timestamp`, or the expiry cannot be represented by the implementation's storage encoding. MUST revert with `InvalidAddress` or `InvalidSelector` under the same conditions as `grant`. MUST emit `PermissionSet`. Because expiry is stored per `(user, operator, target)` blob, updating a selector inside an existing selector bundle also updates the bundle-wide expiry for the other selectors in that blob.

**`grantFull(address operator, address target)`**

MUST grant permanent full-target approval for `(msg.sender, operator, target)`. Full-target approval authorizes the operator to call any selector on `target` until the approval expires or is revoked. MUST revert with `InvalidAddress` if any address argument is `address(0)`. MUST emit `PermissionSet` with `selector == bytes4(0)`.

**`grantFullWithExpiry(address operator, address target, uint48 expiry)`**

MUST grant full-target approval until `expiry`. `type(uint48).max` MUST be treated as permanent. For finite expiries, the function MUST revert with `InvalidExpiry` if `expiry == 0`, `expiry <= block.timestamp`, or the expiry cannot be represented by the implementation's storage encoding. MUST revert with `InvalidAddress` under the same conditions as `grantFull`. MUST emit `PermissionSet` with `selector == bytes4(0)`.

**`grantSelectorBundle(address operator, address target, bytes4[] calldata selectors, uint48 expiry)`**

MUST replace the selector bundle for `(msg.sender, operator, target)` with exactly `selectors` and the provided expiry. `type(uint48).max` MUST be treated as permanent. `selectors` MUST be sorted, unique, and non-empty unless the implementation treats an empty list as full-target approval. MUST revert with `InvalidSelector` for zero, duplicate, or unsorted selectors. MUST revert with `InvalidExpiry` if the expiry is invalid. MUST emit `PermissionSet` for each selector made active.

**`revoke(address operator, address target, bytes4 selector)`**

MUST revoke `selector` from the selector bundle for `(msg.sender, operator, target)`. MUST NOT revert if the selector permission was not previously set. If the current authorization is full-target approval, `revoke` SHOULD NOT partially revoke one selector from the full approval; callers SHOULD use `revokeAll` and then grant a narrower selector bundle. MUST emit `PermissionSet`.

**`revokeAll(address operator, address target)`**

MUST revoke the entire authorization blob for `(msg.sender, operator, target)`. MUST NOT revert if no approval was previously set. MUST emit `PermissionSet` with `selector == bytes4(0)`.

**`grantBatch(PermissionKey[] calldata keys)`**

For each key in `keys`: MUST revert with `PermissionDenied` if `key.user != msg.sender`. Otherwise MUST behave as `grant` for that key. The operation MUST be atomic — if any key causes a revert, no permissions are written.

**`grantBatchWithExpiry(PermissionEntry[] calldata entries)`**

For each entry: MUST revert with `PermissionDenied` if `entry.key.user != msg.sender`. MUST revert with `InvalidExpiry` if the finite expiry is zero, in the past, or cannot be represented. Otherwise MUST behave as `grantWithExpiry`. MUST be atomic. Because expiry is bundle-wide, callers SHOULD avoid mixing different expiries for the same `(user, operator, target)` in a single batch; the final effective expiry for that blob is determined by the resulting authorization blob, not by each selector independently.

**`revokeBatch(PermissionKey[] calldata keys)`**

For each key: MUST revert with `PermissionDenied` if `key.user != msg.sender`. Otherwise MUST behave as `revoke`. MUST be atomic.

### Authorization Queries

**`isAuthorizedCall(address user, address operator, address target, bytes4 selector) → bool`**

MUST return `true` if and only if the authorization blob for `(user, operator, target)` authorizes `selector` and the stored expiry is nonzero and not expired. MUST NOT revert.

For expiry-only blobs, any `selector` MUST be considered authorized while the expiry is valid. For selector-bundle blobs, only selectors present in the bundle MUST be considered authorized. The `InvalidSelector` restriction applies to selector-scoped grants, not to full-target authorization queries.

**`requireAuthorizedCall(address user, address operator, address target, bytes4 selector)`**

MUST revert with `PermissionDenied` if the authorization blob does not authorize `selector`. MUST revert with `PermissionExpired` if the blob authorizes `selector` but the expiry has passed. MUST return without reverting if the permission is valid. The distinction between `PermissionDenied` and `PermissionExpired` is REQUIRED so callers can differentiate between a permission that was never granted and one that has lapsed.

**`permissionExpiry(address user, address operator, address target, bytes4 selector) → uint48`**

MUST return the externally-visible expiry for `selector` under `(user, operator, target)`. If the authorization blob is full-target approval and not empty, this MUST return the full-target expiry for any selector. If `selector` is not authorized, this MUST return `0`. A return value of `type(uint48).max` means permanent.

**`rawPermissionData(address user, address operator, address target) → bytes`**

MUST return the raw authorization blob for `(user, operator, target)`. This function exists for indexers, wallets, and offchain tooling that want to inspect whether an approval is full-target or selector-bundled without testing individual selectors.

### Events

A `PermissionSet` event MUST be emitted on every selector-level change made by `grant`, `grantWithExpiry`, `revoke`, `grantBatch`, `grantBatchWithExpiry`, `revokeBatch`, and `permitPermission`. The `approved` field MUST be `true` if the resulting expiry is nonzero, and `false` if it is `0`. The `expiry` field MUST reflect the externally-visible expiry. For full-target approvals and full revocations, implementations MUST emit `PermissionSet` with `selector == bytes4(0)`.

Implementations SHOULD also emit `AuthorizationSet` when the full authorization blob for `(user, operator, target)` is replaced, including `grantFull`, `grantFullWithExpiry`, `revokeAll`, `grantSelectorBundle`, and `permitFullAuthorization`. `AuthorizationSet` carries decoded state for indexers and wallets: `expiry` plus the active `selectors` array. An empty `selectors` array with nonzero `expiry` means full-target authorization; an empty array with `expiry == 0` means no authorization. Indexers SHOULD prefer `AuthorizationSet` for full-state reconstruction instead of decoding packed bytes differently in every implementation.

### Gasless Permit

**`permitPermission(PermissionPermit calldata permit, bytes calldata signature)`**

Allows a user to authorize or revoke a permission by submitting an EIP-712 signed message, without executing a transaction themselves.

A call to `permitPermission` MUST:

1. Revert with `DeadlineExpired` if `block.timestamp > permit.deadline`.
2. Revert with `InvalidExpiry` if `permit.expiry != 0 && permit.expiry <= block.timestamp`.
3. Revert with `InvalidNonce(current, permit.nonce)` if `permit.nonce` does not equal `permissionNonce[permit.user]`.
4. Revert with `InvalidSignature` if the recovered signer of the EIP-712 digest (defined below) is not `permit.user`.
5. On success: increment `permissionNonce[permit.user]` by 1, apply `permit.expiry` to the selector-scoped permission for `(permit.user, permit.operator, permit.target, permit.selector)`, and emit `PermissionSet`.

The EIP-712 typed data structure is:

```
PermissionPermit(
    address user,
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
    keccak256("PermissionPermit(address user,address operator,address target,bytes4 selector,uint48 expiry,uint256 nonce,uint256 deadline)"),
    permit.user,
    permit.operator,
    permit.target,
    permit.selector,
    permit.expiry,
    permit.nonce,
    permit.deadline
))
```

A `PermissionPermit` signature authorizes a specific selector-scoped change in a specific registry contract on a specific chain. It does not create full-target approval; full-target approvals use the explicit `FullAuthorizationPermit` typed-data flow below so wallets can render stronger warnings for broad authorization.

In human terms, the signed message says:

- **user** — I am authorizing a change to my approval state
- **operator** — this is the address that may act on my behalf
- **target** — this is the contract the operator may call
- **selector** — this is the specific function the operator may call on that contract
- **expiry** — this approval is revoked (`0`), permanent (`type(uint48).max`), or valid until this timestamp
- **nonce** — this authorization can only be used once at this specific nonce
- **deadline** — this signed message itself expires after this timestamp

The signature payload MUST be the EIP-712 typed-data digest formed from the registry's domain separator and the `PermissionPermit` struct hash:

```
keccak256(abi.encodePacked(
    hex"1901",
    DOMAIN_SEPARATOR,
    structHash
))
```

Equivalently, this is the standard EIP-712 encoding of:

- `domain = EIP712Domain(name: "PermissionRegistry", version: "1", chainId, verifyingContract)`
- `message = PermissionPermit(...)`

This means the user is not signing a vague authorization. They are signing an approval that is bound to:

- one registry contract (`verifyingContract`)
- one chain (`chainId`)
- one operator
- one target contract
- one function selector
- one expiry value
- one nonce
- one permit deadline

where `DOMAIN_SEPARATOR` is the EIP-712 domain separator for the registry contract on the current chain.

Wallets and signing applications SHOULD present the `target` and `selector` fields in as human-readable a form as possible. In particular, applications SHOULD attempt to resolve `selector` to a function signature or display label when reliable ABI metadata for `target` is available. If no such metadata is available, applications MUST NOT guess; they SHOULD display the raw selector and make clear that it identifies the specific function being approved.

The `expiry` field in `PermissionPermit` follows the same external encoding as a direct grant: `0` means revoke, `type(uint48).max` means permanent. A single signed permit can therefore express a temporary selector delegation, a permanent selector delegation, or a gasless selector revocation.

The `signature` MUST be a 65-byte `secp256k1` signature in the format `r ++ s ++ v`. High-s signatures MUST be rejected.

**`permitFullAuthorization(FullAuthorizationPermit calldata permit, bytes calldata signature)`**

Allows a user to grant or revoke full-target authorization by submitting an EIP-712 signed message. This is a first-class permit path because full-target approval is the common case for trusted forwarders and agents, and wallets should be able to distinguish it clearly from selector-scoped authorization.

A call to `permitFullAuthorization` MUST follow the same deadline, expiry, nonce, and signature validation rules as `permitPermission`. On success it MUST increment `permissionNonce[permit.user]` by 1 and either:

- if `permit.expiry == 0`, revoke the entire authorization blob for `(permit.user, permit.operator, permit.target)`; or
- otherwise, set an expiry-only full-target authorization blob for `(permit.user, permit.operator, permit.target)`.

The EIP-712 typed data structure is:

```
FullAuthorizationPermit(
    address user,
    address operator,
    address target,
    uint48 expiry,
    uint256 nonce,
    uint256 deadline
)
```

Wallets and signing applications MUST present this as full-target authorization, not as a selector-scoped permit. In human terms, the signed message says: “allow this operator to call any function on this target until expiry,” or revoke that broad authorization when `expiry == 0`.

**`permissionNonce(address user) → uint256`**

MUST return the current nonce for `user`. This value is incremented after each successful `permitPermission` or `permitFullAuthorization` call for that user.

### Recommended Integration Pattern

Integrating contracts SHOULD inherit or re-implement the following modifier pattern:

```solidity
IPermissionRegistry public immutable registry;

modifier onlyAuthorized(address user) {
    if (msg.sender != user) {
        registry.requireAuthorizedCall(user, msg.sender, address(this), msg.sig);
    }
    _;
}
```

The user always retains direct access (`msg.sender == user` bypasses the registry check). Any other caller must hold a valid permission for the calling function's selector on this contract. The `msg.sig` value is the four-byte selector of the currently-executing function, so no additional bookkeeping is required to scope the check to the correct function.

Each function on the target contract that should be independently delegatable MUST apply this modifier separately. Functions applied with the same modifier call are independently grantable — granting permission for one does not affect authorization for any other.

## Rationale

### Three-element storage key plus selector payload

The storage key `(user, operator, target)` is the minimal set of dimensions needed to identify who is delegating, who is being delegated to, and which contract is affected. Function scope is represented inside the authorization blob rather than as the final mapping key.

This is slightly more complex than a four-level `(user, operator, target, selector)` mapping, but it enables an important full-target approval path. For trusted forwarders and automation contracts, users often want to delegate every supported action on a target. Encoding that as an expiry-only blob gives this use case one storage slot and an O(1) authorization check, with gas comparable to a standard ERC-20 approval.

Selector bundles remain available for narrower delegation. They are cheaper to approve than writing one storage slot per selector, but they make selector checks O(n) in the number of selectors scanned. This is an intentional tradeoff: broad trusted delegation gets the cheapest hot path, while narrower delegation pays a small per-check cost for finer scope.

Using `bytes4 selector` instead of a human-readable function string prioritizes canonical onchain correctness over presentation. A selector is unambiguous at the EVM level and cheap to store, compare, and verify. However, selector values alone are not always self-explanatory to end users. This standard therefore makes clear signing possible, but not fully self-describing in isolation: wallet readability depends on the ability of signing software to map `(target, selector)` to verified ABI metadata and present an intelligible function label.

### Wallet rendering and clear signing

This standard is intentionally compatible with wallet-side clear-signing systems, but does not depend on them for correctness. The registry's own authorization flows are designed to be easy for wallets to render because they expose a compact, explicit set of fields: `user`, `operator`, `target`, `auth mode`, `selectors`, and `expiry`.

If a wallet recognizes the registry contract and its ABI or descriptor metadata, it can already present a correct high-level statement such as "Allow `operator` to call selector `0x12345678` on `target` until `expiry`". If the delegated target contract also has verified ABI metadata or a richer descriptor format such as ERC-7730, the wallet MAY further resolve `selector` into a human-readable function label or intent, such as `claim()` or `Claim rewards`.

Accordingly, rich target-level rendering is treated as an ecosystem improvement, not a prerequisite for this ERC. The primitive remains valid and useful even when wallets only support first-class rendering of the registry layer itself.

### Compact expiry encoding

The external interface uses `uint48` expiry values because `0`, finite timestamps, and `type(uint48).max` provide clear user-facing semantics. The packed-auth storage design can store the expiry more compactly. The reference implementation uses `uint32`, where `type(uint32).max` is permanent and finite expiries are valid until February 2106.

This is a deliberate engineering tradeoff. Four bytes lets full-target approvals fit in a short bytes value and keeps selector bundles compact. The year-2106 finite-expiry limit is acceptable for delegated authorization: any approval that needs to outlive that horizon can use the permanent sentinel, and realistic time-bounded permissions are much shorter.

### Distinct PermissionDenied and PermissionExpired errors

Callers that receive `PermissionDenied` know they should prompt the user to grant access. Callers that receive `PermissionExpired` know the user previously delegated but the grant has lapsed — a meaningfully different UX state. Collapsing these into a single error would force callers to query `permissionExpiry` to distinguish them.

### Inclusive expiry boundary

A permission with `expiry == block.timestamp` is considered valid. This matches the convention used by EIP-2612's `deadline` parameter and avoids a one-second off-by-one at the boundary.

### Sequential per-user nonces

Sequential nonces (rather than unordered / bitmap-style nonces as in Permit2) are simpler to reason about and to implement. The tradeoff is that two permits signed by the same user for different operators have an implicit ordering dependency. For the expected use case — a user signs a permit for a single operator, which is submitted before the next is needed — this is not a practical limitation.

### ExecutionPermit not included

An earlier draft included an `executeWithPermit` function: the user signs specific calldata, a relayer submits, and the registry calls the target directly. This was removed because it turns the registry into an execution engine — a different category of primitive that introduces reentrancy surface and requires the registry to appear as `msg.sender` in the target. Any protocol that needs one-shot signed execution can call `permitPermission` and the target function in the same transaction, achieving the same effect without registry-level execution.

### No delegation chains

An operator cannot sub-delegate their permission to a third party. Delegation chains increase the difficulty of auditing what a given address can do and create revocation puzzles (revoking from A does not revoke from B if A already delegated to B). One-hop delegation is sufficient for all anticipated use cases.

## Backwards Compatibility

This ERC introduces a new registry contract and a new modifier pattern. It does not modify any existing standard and is fully additive. Existing ERC-20, ERC-721, and other token contracts are unaffected. Protocols that wish to adopt this standard for new contracts or wrappers can do so without any migration of existing state.

## Test Cases

The reference test suite at [`test/PermissionRegistry.t.sol`](./test/PermissionRegistry.t.sol) covers:

- User direct access (bypasses registry check)
- Granting and revoking single selector permissions
- Full-target approval and revocation
- Selector-bundle approval and sorted selector validation
- Time-bounded grants: valid before expiry, expired after
- Expiry boundary condition (inclusive at `block.timestamp == expiry`)
- Overwriting a permanent grant with a time-bounded one and vice versa
- Batch grant atomicity: a single invalid key reverts the entire batch with no partial writes
- Permission key isolation: grants are scoped to `(user, operator, target)` plus selector payload; a stranger's `revoke` call cannot affect a user's permission
- Operator isolation: an operator cannot revoke the permission granted to them by a user
- Multiple users granting to the same operator are independent
- `permitPermission`: correct selector grant and revoke, wrong signer, expired deadline, skipped nonce, replay rejection
- `permitPermission` with time-bounded expiry
- `permitFullAuthorization`: full-target grant and revoke, shared nonce behavior
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

The ECDSA implementation MUST verify that the recovered signer is not `address(0)`. The reference implementation does so. Implementations that call `ecrecover` directly without this check risk treating malformed signatures as valid grants from a zero-address user.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE).

# ERC Approval Registry

Draft ERC and reference implementation for scoped delegated authorization.

Status: pre-EIP public draft.

## The problem

Today, most onchain delegation is too broad.

If a user wants an operator to do one useful thing — claim fees, compound rewards, rebalance a position, execute through a trusted forwarder — they usually end up choosing between bad options:

- transfer custody into a vault
- grant a broad token approval
- rely on bespoke per-protocol permission logic
- give an automation contract more power than the task actually needs

That is awkward for users, hard for wallets to explain, and non-composable for protocols.

## The core idea

ERC Approval Registry gives contracts a shared authorization primitive:

> Owner authorizes operator to call specific functions on a target contract, without transferring custody.

A permission is scoped by:

- owner — whose position/account/assets are being acted on
- operator — who is allowed to act
- target — which contract they may call
- selector — which function they may call, unless the owner grants full-target approval
- expiry — when the permission stops working

The registry supports two modes:

- **Selector approval** for narrow permissions like `claim()` but not `transfer()`
- **Full-target approval** for trusted forwarders where the user intentionally delegates the whole target surface

## What integration looks like

An integrating contract only needs to ask the registry before allowing an operator to act for an owner.

```solidity
modifier onlyAuthorized(address owner) {
    if (msg.sender != owner) {
        registry.requireAuthorizedCall(owner, msg.sender, address(this), msg.sig);
    }
    _;
}
```

The target contract does not need to know whether the user granted full-target approval or a selector bundle. It just asks whether `msg.sender` is authorized for `msg.sig`.

## Simple example

A user owns an LP position managed by a wrapper contract.

They want a bot to claim fees, but they do **not** want the bot to transfer the position.

With the registry, the user grants the bot permission for only the claim selector on the wrapper target:

```solidity
registry.grant(
    bot,
    address(lpWrapper),
    lpWrapper.claim.selector
);
```

Now the bot can call `claim()` for that user, but calls to more sensitive functions like `transferManagedPosition()` fail unless separately authorized.

## Why this is useful

For users:

- keep custody of positions and accounts
- delegate specific actions instead of broad control
- use expiries for temporary automation
- revoke permissions from one standard place

For protocols:

- add delegated execution with a small modifier
- avoid building bespoke permission systems
- support automation, social trading, keepers, trusted forwarders, and intent flows
- give wallets and indexers a common permission surface to display

For wallets and agents:

- permissions have a stable shape: owner, operator, target, selectors, expiry
- selector-scoped approvals can be rendered more clearly than token allowances
- revocation and permission discovery can be standardized across apps

## Example behaviors covered in this repo

### LP wrapper

- authorize `claim()`
- do **not** authorize `transferManagedPosition()`

### Staking wrapper

- authorize `claimRewards()`
- do **not** authorize `unstake()`

### Treasury-like target

- authorize `rebalance()`
- do **not** authorize `transferTreasuryControl()`

## What is in here

### Core

- `src/PermissionRegistry.sol`
- `src/interfaces/IPermissionRegistry.sol`
- `src/base/PermissionedTarget.sol`

### Examples

- `src/examples/UniV3LPWrapper.sol`
- `src/examples/StakingRewardsWrapper.sol`
- `src/examples/SimpleTreasury.sol`

### Mocks

- `src/examples/MockUniV3PositionManager.sol`
- `src/examples/MockStakingRewardsManager.sol`

### Tests

- `test/PermissionRegistry.t.sol`
- `test/AuthGasBench.t.sol`

## Grant types

The public interface includes:

```solidity
function grant(address operator, address target, bytes4 selector) external;
function grantWithExpiry(address operator, address target, bytes4 selector, uint48 expiry) external;
function revoke(address operator, address target, bytes4 selector) external;

function grantFull(address operator, address target) external;
function grantFullWithExpiry(address operator, address target, uint48 expiry) external;
function revokeAll(address operator, address target) external;

function grantSelectorBundle(address operator, address target, bytes4[] calldata selectors, uint48 expiry) external;
```

Use selector grants when the operator should only do specific actions. Use full-target grants when the operator is a trusted forwarder or module that intentionally needs the whole target surface.

One important semantic constraint: expiry is bundle-wide for a given `(owner, operator, target)`. If you need different expiries for different actions, use separate operators/targets or update the bundle intentionally.

## Implementation notes

The current canonical design stores one compact authorization blob per `(owner, operator, target)`.

The blob can represent:

- no approval
- full-target approval
- selector-bundle approval

Canonical encoding:

```text
auth.length == 0: no approval
auth.length == 4: expiry only = full target approval
auth.length > 4: uint32 expiry || sorted bytes4 selectors...
```

Expiry rules:

- `0` means revoked / not set
- `uint32.max` is the internal permanent sentinel
- external APIs expose `type(uint48).max` as permanent
- finite `uint32` timestamps are valid until February 2106

The packed representation gives a cheap forwarder path while making selector bundles much cheaper to grant than writing one storage slot per selector.

## Gas summary

See [`Gas analysis.md`](./Gas%20analysis.md) for the detailed measurements.

Short version:

- Full-target approval is roughly ERC20 approval territory.
- Full-target checks are O(1) and measured around 2.6k gas in the reference implementation.
- Selector bundles are much cheaper to approve than writing one storage slot per selector.
- Selector-bundle checks are O(n), so large bundles are not ideal for very hot partial-permission paths.

The intended tradeoff:

- trusted forwarder → use full-target approval
- narrow occasional delegation → use selector bundle
- extremely hot narrow delegation → be aware of bundle scan cost

## Draft materials

- [`SPEC.md`](./SPEC.md) — draft ERC text
- [`Gas analysis.md`](./Gas%20analysis.md) — gas comparison and tradeoffs
- [`docs/ethereum-magicians-post.md`](./docs/ethereum-magicians-post.md) — prepared forum post draft

## Run tests

```bash
~/.foundry/bin/forge test
```

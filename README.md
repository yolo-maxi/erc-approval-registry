# ERC Permissions

A reference repo for a registry-based delegated authorization primitive.

## Core idea

An owner can authorize an operator on a target contract without transferring custody.

The new canonical design stores one compact authorization blob per:

- owner
- operator
- target

The blob can represent:

- no approval
- full-target approval
- selector-bundle approval

That gives us a cheap forwarder path while still supporting narrower permissions.

## Authorization encoding

```text
auth.length == 0: no approval
auth.length == 4: expiry only = full target approval
auth.length > 4: uint32 expiry || sorted bytes4 selectors...
```

Expiry rules:

- `0` means revoked / not set
- `uint32.max` is the internal permanent sentinel
- external APIs still expose `type(uint48).max` as permanent
- finite `uint32` timestamps are valid until February 2106

Full-target approval is useful for trusted forwarders where the user wants to delegate the whole target surface. Selector bundles are useful when the user wants narrower authorization such as:

- `claim()` on an LP wrapper
- `claimRewards()` on a staking wrapper
- `rebalance()` on a treasury-like target

without also authorizing more sensitive functions.

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

## Integration pattern

```solidity
modifier onlyAuthorized(address owner) {
    if (msg.sender != owner) {
        registry.requireAuthorizedCall(owner, msg.sender, address(this), msg.sig);
    }
    _;
}
```

The target contract does not need to know whether the user granted full-target approval or a selector bundle. It just asks the registry whether `msg.sender` is authorized for `msg.sig`.

## Example behaviors covered

### LP wrapper

- authorize `claim()`
- do **not** authorize `transferManagedPosition()`

### Staking wrapper

- authorize `claimRewards()`
- do **not** authorize `unstake()`

### Treasury-like target

- authorize `rebalance()`
- do **not** authorize `transferTreasuryControl()`

## Run tests

```bash
~/.foundry/bin/forge test
```

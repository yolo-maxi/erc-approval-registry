# ERC Permissions

A super simple reference repo for a registry-based delegated auth primitive.

## Core idea

An owner can authorize:

- one operator
- on one target
- for one function selector

So instead of broad custody or blanket approvals, a user can authorize a narrow action like:

- `claim()` on an LP wrapper
- `claimRewards()` on a staking wrapper
- `rebalance()` on a treasury-like target

without also authorizing more sensitive functions.

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

## Integration pattern

```solidity
modifier onlyAuthorized(address owner) {
    if (msg.sender != owner) {
        registry.requireAuthorizedCall(owner, msg.sender, address(this), msg.sig);
    }
    _;
}
```

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

That is the whole point: each function has its own auth surface.

## Run tests

```bash
~/.foundry/bin/forge test
```

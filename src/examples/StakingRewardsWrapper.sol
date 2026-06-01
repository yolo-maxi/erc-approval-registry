// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PermissionedTarget} from "../base/PermissionedTarget.sol";
import {MockStakingRewardsManager} from "./MockStakingRewardsManager.sol";

/// @notice Example wrapper for staking positions with function-scoped permissions.
contract StakingRewardsWrapper is PermissionedTarget {
    struct ManagedStake {
        address user;
        uint256 positionId;
    }

    MockStakingRewardsManager public immutable manager;
    uint256 public nextManagedId = 1;
    mapping(uint256 managedId => ManagedStake stakePosition) public managedStakes;

    event ManagedStakeOpened(uint256 indexed managedId, address indexed user, uint256 indexed positionId);
    event RewardsClaimed(uint256 indexed managedId, address indexed recipient, uint256 amount);
    event Unstaked(uint256 indexed managedId, uint128 amount);
    event ManagedStakeTransferred(uint256 indexed managedId, address indexed oldUser, address indexed newUser);

    constructor(address registry_, address manager_) PermissionedTarget(registry_) {
        manager = MockStakingRewardsManager(manager_);
    }

    function openManagedStake(address user, uint128 amount)
        external
        onlyAuthorized(user)
        returns (uint256 managedId, uint256 positionId)
    {
        positionId = manager.openPosition(user, amount);
        managedId = nextManagedId++;
        managedStakes[managedId] = ManagedStake({user: user, positionId: positionId});
        emit ManagedStakeOpened(managedId, user, positionId);
    }

    function claimRewards(uint256 managedId, address recipient)
        external
        onlyAuthorized(managedStakes[managedId].user)
        returns (uint256 amount)
    {
        ManagedStake memory stakePosition = managedStakes[managedId];
        amount = manager.claimRewards(stakePosition.positionId, recipient);
        emit RewardsClaimed(managedId, recipient, amount);
    }

    function unstake(uint256 managedId, uint128 amount) external onlyAuthorized(managedStakes[managedId].user) {
        manager.unstake(managedStakes[managedId].positionId, amount);
        emit Unstaked(managedId, amount);
    }

    function transferManagedStake(uint256 managedId, address newUser)
        external
        onlyAuthorized(managedStakes[managedId].user)
    {
        address oldUser = managedStakes[managedId].user;
        managedStakes[managedId].user = newUser;
        emit ManagedStakeTransferred(managedId, oldUser, newUser);
    }
}

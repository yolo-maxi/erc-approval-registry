// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract MockStakingRewardsManager {
    struct Position {
        address owner;
        uint128 stakedAmount;
        uint256 rewards;
    }

    uint256 public nextPositionId = 1;
    mapping(uint256 positionId => Position position) public positions;

    event PositionOpened(uint256 indexed positionId, address indexed owner, uint128 amount);
    event RewardsClaimed(uint256 indexed positionId, address indexed recipient, uint256 amount);
    event Unstaked(uint256 indexed positionId, uint128 amount);

    function openPosition(address owner, uint128 amount) external returns (uint256 positionId) {
        positionId = nextPositionId++;
        positions[positionId] = Position({owner: owner, stakedAmount: amount, rewards: 0});
        emit PositionOpened(positionId, owner, amount);
    }

    function seedRewards(uint256 positionId, uint256 amount) external {
        positions[positionId].rewards += amount;
    }

    function claimRewards(uint256 positionId, address recipient) external returns (uint256 amount) {
        Position storage position = positions[positionId];
        amount = position.rewards;
        position.rewards = 0;
        emit RewardsClaimed(positionId, recipient, amount);
    }

    function unstake(uint256 positionId, uint128 amount) external {
        positions[positionId].stakedAmount -= amount;
        emit Unstaked(positionId, amount);
    }
}

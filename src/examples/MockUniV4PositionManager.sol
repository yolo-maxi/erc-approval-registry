// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract MockUniV4PositionManager {
    struct PoolPosition {
        address owner;
        bytes32 poolId;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 fees0;
        uint256 fees1;
    }

    uint256 public nextPositionId = 1;
    mapping(uint256 positionId => PoolPosition position) public positions;

    event PositionOpened(uint256 indexed positionId, address indexed owner, bytes32 indexed poolId, uint128 liquidity);
    event PositionAdjusted(uint256 indexed positionId, int128 liquidityDelta);
    event FeesClaimed(uint256 indexed positionId, address indexed recipient, uint256 amount0, uint256 amount1);

    function openPosition(address owner, bytes32 poolId, int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        returns (uint256 positionId)
    {
        positionId = nextPositionId++;
        positions[positionId] = PoolPosition({
            owner: owner,
            poolId: poolId,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: liquidity,
            fees0: 0,
            fees1: 0
        });
        emit PositionOpened(positionId, owner, poolId, liquidity);
    }

    function seedFees(uint256 positionId, uint256 amount0, uint256 amount1) external {
        PoolPosition storage p = positions[positionId];
        p.fees0 += amount0;
        p.fees1 += amount1;
    }

    function modifyLiquidity(uint256 positionId, int128 liquidityDelta) external {
        PoolPosition storage p = positions[positionId];
        if (liquidityDelta >= 0) {
            p.liquidity += uint128(uint128(liquidityDelta));
        } else {
            p.liquidity -= uint128(uint128(-liquidityDelta));
        }
        emit PositionAdjusted(positionId, liquidityDelta);
    }

    function claimFees(uint256 positionId, address recipient) external returns (uint256 amount0, uint256 amount1) {
        PoolPosition storage p = positions[positionId];
        amount0 = p.fees0;
        amount1 = p.fees1;
        p.fees0 = 0;
        p.fees1 = 0;
        emit FeesClaimed(positionId, recipient, amount0, amount1);
    }
}

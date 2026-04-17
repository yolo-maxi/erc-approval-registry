// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PermissionedTarget} from "../base/PermissionedTarget.sol";
import {MockUniV4PositionManager} from "./MockUniV4PositionManager.sol";

/// @notice Example v4-style wrapper demonstrating the same permission UX for pool-position management.
contract UniV4LPWrapper is PermissionedTarget {
    MockUniV4PositionManager public immutable positionManager;

    struct ManagedPoolPosition {
        address owner;
        uint256 positionId;
    }

    mapping(uint256 managedId => ManagedPoolPosition position) public managedPositions;
    uint256 public nextManagedId = 1;

    event ManagedPoolPositionOpened(uint256 indexed managedId, address indexed owner, uint256 indexed positionId);
    event ManagedPoolLiquidityAdjusted(uint256 indexed managedId, int128 delta, address indexed actor);
    event ManagedPoolFeesClaimed(uint256 indexed managedId, address indexed recipient, uint256 amount0, uint256 amount1);

    constructor(address registry, address _positionManager) PermissionedTarget(registry) {
        positionManager = MockUniV4PositionManager(_positionManager);
    }

    function openManagedPosition(address owner, bytes32 poolId, int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        onlyOwnerOrAuthorized(owner)
        returns (uint256 managedId, uint256 positionId)
    {
        positionId = positionManager.openPosition(owner, poolId, tickLower, tickUpper, liquidity);
        managedId = nextManagedId++;
        managedPositions[managedId] = ManagedPoolPosition({owner: _ownerFromExecution(owner), positionId: positionId});
        emit ManagedPoolPositionOpened(managedId, owner, positionId);
    }

    function rebalance(uint256 managedId, int128 liquidityDelta)
        external
        onlyOwnerOrAuthorized(managedPositions[managedId].owner)
    {
        positionManager.modifyLiquidity(managedPositions[managedId].positionId, liquidityDelta);
        emit ManagedPoolLiquidityAdjusted(managedId, liquidityDelta, _actor());
    }

    function claimFees(uint256 managedId, address recipient)
        external
        onlyOwnerOrAuthorized(managedPositions[managedId].owner)
        returns (uint256 amount0, uint256 amount1)
    {
        ManagedPoolPosition memory p = managedPositions[managedId];
        (amount0, amount1) = positionManager.claimFees(p.positionId, recipient);
        emit ManagedPoolFeesClaimed(managedId, recipient, amount0, amount1);
    }
}

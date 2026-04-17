// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PermissionedTarget} from "../base/PermissionedTarget.sol";
import {MockUniV3PositionManager} from "./MockUniV3PositionManager.sol";

/// @notice Example non-custodial wrapper that gates LP management actions with the permission registry.
contract UniV3LPWrapper is PermissionedTarget {
    MockUniV3PositionManager public immutable positionManager;

    struct ManagedPosition {
        address owner;
        uint256 tokenId;
    }

    mapping(uint256 managedId => ManagedPosition position) public managedPositions;
    uint256 public nextManagedId = 1;

    event ManagedPositionOpened(uint256 indexed managedId, address indexed owner, uint256 indexed tokenId);
    event ManagedLiquidityAdded(uint256 indexed managedId, uint128 amount, address indexed actor);
    event ManagedFeesCollected(uint256 indexed managedId, address indexed recipient, uint256 amount0, uint256 amount1);

    constructor(address registry, address _positionManager) PermissionedTarget(registry) {
        positionManager = MockUniV3PositionManager(_positionManager);
    }

    function openManagedPosition(address owner, int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        onlyOwnerOrAuthorized(owner)
        returns (uint256 managedId, uint256 tokenId)
    {
        tokenId = positionManager.mint(owner, tickLower, tickUpper, liquidity);
        managedId = nextManagedId++;
        managedPositions[managedId] = ManagedPosition({owner: _ownerFromExecution(owner), tokenId: tokenId});
        emit ManagedPositionOpened(managedId, owner, tokenId);
    }

    function addLiquidity(uint256 managedId, uint128 amount) external onlyOwnerOrAuthorized(managedPositions[managedId].owner) {
        positionManager.increaseLiquidity(managedPositions[managedId].tokenId, amount);
        emit ManagedLiquidityAdded(managedId, amount, _actor());
    }

    function collectFees(uint256 managedId, address recipient)
        external
        onlyOwnerOrAuthorized(managedPositions[managedId].owner)
        returns (uint256 amount0, uint256 amount1)
    {
        ManagedPosition memory p = managedPositions[managedId];
        (amount0, amount1) = positionManager.collect(p.tokenId, recipient);
        emit ManagedFeesCollected(managedId, recipient, amount0, amount1);
    }
}

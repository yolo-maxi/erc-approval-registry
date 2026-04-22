// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PermissionedTarget} from "../base/PermissionedTarget.sol";
import {MockUniV3PositionManager} from "./MockUniV3PositionManager.sol";

/// @notice Very small example wrapper showing per-function permissions on LP management actions.
contract UniV3LPWrapper is PermissionedTarget {
    struct ManagedPosition {
        address owner;
        uint256 tokenId;
    }

    MockUniV3PositionManager public immutable positionManager;
    uint256 public nextManagedId = 1;
    mapping(uint256 managedId => ManagedPosition position) public managedPositions;

    event ManagedPositionOpened(uint256 indexed managedId, address indexed owner, uint256 indexed tokenId);
    event LiquidityAdded(uint256 indexed managedId, uint128 amount);
    event FeesClaimed(uint256 indexed managedId, address indexed recipient, uint256 amount0, uint256 amount1);
    event ManagedPositionTransferred(uint256 indexed managedId, address indexed oldOwner, address indexed newOwner);

    constructor(address registry_, address positionManager_) PermissionedTarget(registry_) {
        positionManager = MockUniV3PositionManager(positionManager_);
    }

    function openManagedPosition(address owner, int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        onlyAuthorized(owner)
        returns (uint256 managedId, uint256 tokenId)
    {
        tokenId = positionManager.mint(owner, tickLower, tickUpper, liquidity);
        managedId = nextManagedId++;
        managedPositions[managedId] = ManagedPosition({owner: owner, tokenId: tokenId});
        emit ManagedPositionOpened(managedId, owner, tokenId);
    }

    function addLiquidity(uint256 managedId, uint128 amount)
        external
        onlyAuthorized(managedPositions[managedId].owner)
    {
        positionManager.increaseLiquidity(managedPositions[managedId].tokenId, amount);
        emit LiquidityAdded(managedId, amount);
    }

    /// @notice Claim fees without granting blanket control over the position.
    function claim(uint256 managedId, address recipient)
        external
        onlyAuthorized(managedPositions[managedId].owner)
        returns (uint256 amount0, uint256 amount1)
    {
        ManagedPosition memory position = managedPositions[managedId];
        (amount0, amount1) = positionManager.claim(position.tokenId, recipient);
        emit FeesClaimed(managedId, recipient, amount0, amount1);
    }

    /// @notice Example of a more sensitive function that can remain ungranted while claim() is allowed.
    function transferManagedPosition(uint256 managedId, address newOwner)
        external
        onlyAuthorized(managedPositions[managedId].owner)
    {
        address oldOwner = managedPositions[managedId].owner;
        managedPositions[managedId].owner = newOwner;
        emit ManagedPositionTransferred(managedId, oldOwner, newOwner);
    }
}

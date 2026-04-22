// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPermissionRegistry} from "../interfaces/IPermissionRegistry.sol";

/// @title PermissionedTarget
/// @notice Minimal integration helper: owner can call directly, otherwise caller needs an explicit permission.
abstract contract PermissionedTarget {
    IPermissionRegistry public immutable registry;

    constructor(address registry_) {
        registry = IPermissionRegistry(registry_);
    }

    modifier onlyAuthorized(address owner) {
        _requireAuthorized(owner);
        _;
    }

    /// @dev Backwards-compatible alias for older examples in the repo.
    modifier onlyOwnerOrAuthorized(address owner) {
        _requireAuthorized(owner);
        _;
    }

    function _requireAuthorized(address owner) internal view {
        if (msg.sender == owner) return;
        registry.requireAuthorizedCall(owner, msg.sender, address(this), msg.sig);
    }

    /// @dev Kept only so older example files continue compiling.
    function _actor() internal view returns (address) {
        return msg.sender;
    }

    /// @dev Kept only so older example files continue compiling.
    function _ownerFromExecution(address fallbackOwner) internal pure returns (address) {
        return fallbackOwner;
    }
}

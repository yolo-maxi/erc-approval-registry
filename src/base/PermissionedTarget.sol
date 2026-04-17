// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPermissionRegistry} from "../interfaces/IPermissionRegistry.sol";

/// @title PermissionedTarget
/// @notice Minimal base helper for integrating contracts that want owner/operator permissions.
abstract contract PermissionedTarget {
    IPermissionRegistry public immutable permissionRegistry;

    constructor(address registry) {
        permissionRegistry = IPermissionRegistry(registry);
    }

    modifier onlyOwnerOrAuthorized(address owner) {
        _checkOwnerOrAuthorized(owner);
        _;
    }

    function _checkOwnerOrAuthorized(address owner) internal view {
        if (msg.sender == owner) return;

        address actor = _actor();
        if (permissionRegistry.isAuthorizedCall(owner, actor, address(this), msg.sig)) return;

        revert IPermissionRegistry.PermissionDenied(owner, actor, address(this), msg.sig);
    }

    function _actor() internal view returns (address) {
        if (msg.sender == address(permissionRegistry)) {
            return permissionRegistry.activeExecutionOperator();
        }
        return msg.sender;
    }

    function _ownerFromExecution(address fallbackOwner) internal view returns (address) {
        if (msg.sender == address(permissionRegistry)) {
            return permissionRegistry.activeExecutionOwner();
        }
        return fallbackOwner;
    }
}

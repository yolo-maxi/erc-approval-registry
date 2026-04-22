// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPermissionRegistry} from "./interfaces/IPermissionRegistry.sol";

/// @title PermissionRegistry
/// @notice Tiny registry for permissions scoped to (owner, operator, target, selector).
contract PermissionRegistry is IPermissionRegistry {
    mapping(address owner => mapping(address operator => mapping(address target => mapping(bytes4 selector => bool))))
        internal permissions;

    function grant(address operator, address target, bytes4 selector) external {
        _set(msg.sender, operator, target, selector, true);
    }

    function revoke(address operator, address target, bytes4 selector) external {
        _set(msg.sender, operator, target, selector, false);
    }

    function grantBatch(PermissionKey[] calldata keys) external {
        uint256 length = keys.length;
        for (uint256 i; i < length; ++i) {
            PermissionKey calldata key = keys[i];
            if (key.owner != msg.sender) revert PermissionDenied(key.owner, msg.sender, key.target, key.selector);
            _set(key.owner, key.operator, key.target, key.selector, true);
        }
    }

    function revokeBatch(PermissionKey[] calldata keys) external {
        uint256 length = keys.length;
        for (uint256 i; i < length; ++i) {
            PermissionKey calldata key = keys[i];
            if (key.owner != msg.sender) revert PermissionDenied(key.owner, msg.sender, key.target, key.selector);
            _set(key.owner, key.operator, key.target, key.selector, false);
        }
    }

    function isAuthorizedCall(address owner, address operator, address target, bytes4 selector)
        external
        view
        returns (bool)
    {
        return permissions[owner][operator][target][selector];
    }

    function requireAuthorizedCall(address owner, address operator, address target, bytes4 selector) external view {
        if (!permissions[owner][operator][target][selector]) {
            revert PermissionDenied(owner, operator, target, selector);
        }
    }

    function _set(address owner, address operator, address target, bytes4 selector, bool approved) internal {
        if (owner == address(0) || operator == address(0) || target == address(0)) revert InvalidAddress();
        if (selector == bytes4(0)) revert InvalidSelector();

        permissions[owner][operator][target][selector] = approved;
        emit PermissionSet(owner, operator, target, selector, approved);
    }
}

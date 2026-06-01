// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPermissionRegistry} from "../interfaces/IPermissionRegistry.sol";

/// @title PermissionedTarget
/// @notice Minimal integration helper. The user can always call directly; anyone else needs an
///         explicit permission in the registry for this contract and selector.
abstract contract PermissionedTarget {
    IPermissionRegistry public immutable registry;

    constructor(address registry_) {
        registry = IPermissionRegistry(registry_);
    }

    modifier onlyAuthorized(address user) {
        if (msg.sender != user) {
            registry.requireAuthorizedCall(user, msg.sender, address(this), msg.sig);
        }
        _;
    }
}

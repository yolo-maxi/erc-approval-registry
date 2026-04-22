// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IPermissionRegistry {
    struct PermissionKey {
        address owner;
        address operator;
        address target;
        bytes4 selector;
    }

    error PermissionDenied(address owner, address operator, address target, bytes4 selector);
    error InvalidAddress();
    error InvalidSelector();

    event PermissionSet(
        address indexed owner,
        address indexed operator,
        address indexed target,
        bytes4 selector,
        bool approved
    );

    function grant(address operator, address target, bytes4 selector) external;
    function revoke(address operator, address target, bytes4 selector) external;

    function grantBatch(PermissionKey[] calldata keys) external;
    function revokeBatch(PermissionKey[] calldata keys) external;

    function isAuthorizedCall(address owner, address operator, address target, bytes4 selector)
        external
        view
        returns (bool);

    function requireAuthorizedCall(address owner, address operator, address target, bytes4 selector) external view;
}

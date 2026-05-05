// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPermissionRegistry} from "./interfaces/IPermissionRegistry.sol";
import {EIP712} from "./utils/EIP712.sol";
import {ECDSA} from "./utils/ECDSA.sol";

/// @title PermissionRegistry
/// @notice Registry for permissions scoped to (owner, operator, target, selector).
///
/// Storage encoding: uint48 expiry where
///   0                = not granted / revoked
///   type(uint48).max = permanent
///   anything else    = expiry timestamp (Unix seconds)
contract PermissionRegistry is IPermissionRegistry, EIP712 {
    uint48 internal constant PERMANENT = type(uint48).max;

    bytes32 public constant PERMISSION_PERMIT_TYPEHASH = keccak256(
        "PermissionPermit(address owner,address operator,address target,bytes4 selector,uint48 expiry,uint256 nonce,uint256 deadline)"
    );

    mapping(address owner => mapping(address operator => mapping(address target => mapping(bytes4 selector => uint48))))
        internal permissions;

    mapping(address owner => uint256) public permissionNonce;

    constructor() EIP712("PermissionRegistry", "1") {}

    // -------------------------------------------------------------------------
    // Standing permission management
    // -------------------------------------------------------------------------

    function grant(address operator, address target, bytes4 selector) external {
        _set(msg.sender, operator, target, selector, PERMANENT);
    }

    function grantWithExpiry(address operator, address target, bytes4 selector, uint48 expiry) external {
        if (expiry == 0 || expiry <= uint48(block.timestamp)) revert InvalidExpiry();
        _set(msg.sender, operator, target, selector, expiry);
    }

    function revoke(address operator, address target, bytes4 selector) external {
        _set(msg.sender, operator, target, selector, 0);
    }

    function grantBatch(PermissionKey[] calldata keys) external {
        uint256 length = keys.length;
        for (uint256 i; i < length; ++i) {
            PermissionKey calldata key = keys[i];
            if (key.owner != msg.sender) revert PermissionDenied(key.owner, msg.sender, key.target, key.selector);
            _set(key.owner, key.operator, key.target, key.selector, PERMANENT);
        }
    }

    function grantBatchWithExpiry(PermissionEntry[] calldata entries) external {
        uint256 length = entries.length;
        for (uint256 i; i < length; ++i) {
            PermissionEntry calldata entry = entries[i];
            PermissionKey calldata key = entry.key;
            if (key.owner != msg.sender) revert PermissionDenied(key.owner, msg.sender, key.target, key.selector);
            if (entry.expiry == 0 || entry.expiry <= uint48(block.timestamp)) revert InvalidExpiry();
            _set(key.owner, key.operator, key.target, key.selector, entry.expiry);
        }
    }

    function revokeBatch(PermissionKey[] calldata keys) external {
        uint256 length = keys.length;
        for (uint256 i; i < length; ++i) {
            PermissionKey calldata key = keys[i];
            if (key.owner != msg.sender) revert PermissionDenied(key.owner, msg.sender, key.target, key.selector);
            _set(key.owner, key.operator, key.target, key.selector, 0);
        }
    }

    // -------------------------------------------------------------------------
    // Signed permit
    // -------------------------------------------------------------------------

    function permitPermission(PermissionPermit calldata permit, bytes calldata signature) external {
        if (block.timestamp > permit.deadline) revert DeadlineExpired();
        if (permit.expiry != 0 && permit.expiry <= uint48(block.timestamp)) revert InvalidExpiry();

        uint256 nonce = permissionNonce[permit.owner];
        if (permit.nonce != nonce) revert InvalidNonce(nonce, permit.nonce);

        bytes32 structHash = keccak256(
            abi.encode(
                PERMISSION_PERMIT_TYPEHASH,
                permit.owner,
                permit.operator,
                permit.target,
                permit.selector,
                permit.expiry,
                permit.nonce,
                permit.deadline
            )
        );
        address signer = ECDSA.recover(_hashTypedData(structHash), bytes(signature));
        if (signer != permit.owner) revert InvalidSignature();

        permissionNonce[permit.owner] = nonce + 1;
        _set(permit.owner, permit.operator, permit.target, permit.selector, permit.expiry);
    }

    // -------------------------------------------------------------------------
    // Authorization queries
    // -------------------------------------------------------------------------

    function isAuthorizedCall(address owner, address operator, address target, bytes4 selector)
        external
        view
        returns (bool)
    {
        uint48 expiry = permissions[owner][operator][target][selector];
        return expiry != 0 && block.timestamp <= expiry;
    }

    function requireAuthorizedCall(address owner, address operator, address target, bytes4 selector) external view {
        uint48 expiry = permissions[owner][operator][target][selector];
        if (expiry == 0) revert PermissionDenied(owner, operator, target, selector);
        if (block.timestamp > expiry) revert PermissionExpired(owner, operator, target, selector);
    }

    function permissionExpiry(address owner, address operator, address target, bytes4 selector)
        external
        view
        returns (uint48)
    {
        return permissions[owner][operator][target][selector];
    }

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    function _set(address owner, address operator, address target, bytes4 selector, uint48 expiry) internal {
        if (owner == address(0) || operator == address(0) || target == address(0)) revert InvalidAddress();
        if (selector == bytes4(0)) revert InvalidSelector();

        permissions[owner][operator][target][selector] = expiry;
        emit PermissionSet(owner, operator, target, selector, expiry != 0, expiry);
    }
}

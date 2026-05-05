// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IPermissionRegistry {
    // -------------------------------------------------------------------------
    // Data structures
    // -------------------------------------------------------------------------

    struct PermissionKey {
        address owner;
        address operator;
        address target;
        bytes4 selector;
    }

    /// @notice Used by grantBatchWithExpiry to bundle a key with its expiry.
    struct PermissionEntry {
        PermissionKey key;
        uint48 expiry;
    }

    /// @notice Signed permit for gasless off-chain permission grants/revokes.
    /// @dev expiry semantics: 0 = revoke, type(uint48).max = permanent, else = expiry timestamp.
    ///      Validated: if expiry != 0, expiry must be in the future.
    struct PermissionPermit {
        address owner;
        address operator;
        address target;
        bytes4 selector;
        uint48 expiry;
        uint256 nonce;
        uint256 deadline;
    }

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error PermissionDenied(address owner, address operator, address target, bytes4 selector);
    /// @notice Thrown by requireAuthorizedCall when a permission existed but has passed its expiry.
    error PermissionExpired(address owner, address operator, address target, bytes4 selector);
    error InvalidAddress();
    error InvalidSelector();
    /// @notice Thrown when a granted expiry is zero or already in the past.
    error InvalidExpiry();
    error InvalidSignature();
    error DeadlineExpired();
    error InvalidNonce(uint256 expected, uint256 actual);

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted on every permission change.
    /// @param expiry type(uint48).max = permanent; 0 = revoked; else = expiry timestamp.
    event PermissionSet(
        address indexed owner,
        address indexed operator,
        address indexed target,
        bytes4 selector,
        bool approved,
        uint48 expiry
    );

    // -------------------------------------------------------------------------
    // Standing permission management
    // -------------------------------------------------------------------------

    /// @notice Grant a permanent standing permission.
    function grant(address operator, address target, bytes4 selector) external;

    /// @notice Grant a time-bounded standing permission. expiry must be strictly in the future.
    function grantWithExpiry(address operator, address target, bytes4 selector, uint48 expiry) external;

    function revoke(address operator, address target, bytes4 selector) external;

    /// @notice Batch-grant permanent permissions. All keys must have owner == msg.sender.
    function grantBatch(PermissionKey[] calldata keys) external;

    /// @notice Batch-grant time-bounded permissions. All keys must have owner == msg.sender.
    function grantBatchWithExpiry(PermissionEntry[] calldata entries) external;

    function revokeBatch(PermissionKey[] calldata keys) external;

    // -------------------------------------------------------------------------
    // Signed permit
    // -------------------------------------------------------------------------

    /// @notice Gasless permission grant/revoke: owner signs off-chain, anyone submits on-chain.
    function permitPermission(PermissionPermit calldata permit, bytes calldata signature) external;

    // -------------------------------------------------------------------------
    // Authorization queries
    // -------------------------------------------------------------------------

    function isAuthorizedCall(address owner, address operator, address target, bytes4 selector)
        external
        view
        returns (bool);

    function requireAuthorizedCall(address owner, address operator, address target, bytes4 selector) external view;

    /// @notice Returns the raw stored expiry: 0 = not granted, type(uint48).max = permanent, else = expiry timestamp.
    function permissionExpiry(address owner, address operator, address target, bytes4 selector)
        external
        view
        returns (uint48);

    // -------------------------------------------------------------------------
    // Nonce
    // -------------------------------------------------------------------------

    function permissionNonce(address owner) external view returns (uint256);
}

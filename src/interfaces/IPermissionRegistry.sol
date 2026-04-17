// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IPermissionRegistry {
    struct PermissionKey {
        address owner;
        address operator;
        address target;
        bytes4 selector;
    }

    struct PermissionPermit {
        address owner;
        address operator;
        address target;
        bytes4 selector;
        bool approved;
        uint256 nonce;
        uint256 deadline;
    }

    struct ExecutionPermit {
        address owner;
        address operator;
        address target;
        bytes4 selector;
        bytes32 calldataHash;
        uint256 value;
        uint256 nonce;
        uint256 deadline;
    }

    error PermissionDenied(address owner, address operator, address target, bytes4 selector);
    error InvalidSignature();
    error DeadlineExpired();
    error InvalidNonce(uint256 expected, uint256 actual);
    error InvalidTarget();
    error InvalidSelector();
    error InvalidCalldataHash();
    error CallFailed(bytes revertData);

    event PermissionSet(
        address indexed owner,
        address indexed operator,
        address indexed target,
        bytes4 selector,
        bool approved
    );

    event ExecutionPermitUsed(
        address indexed owner,
        address indexed operator,
        address indexed target,
        bytes4 selector,
        bytes32 calldataHash,
        uint256 nonce
    );

    function grant(address operator, address target, bytes4 selector) external;
    function revoke(address operator, address target, bytes4 selector) external;

    function grantBatch(PermissionKey[] calldata keys) external;
    function revokeBatch(PermissionKey[] calldata keys) external;

    function permitPermission(PermissionPermit calldata permit, bytes calldata signature) external;

    function executeWithPermit(
        ExecutionPermit calldata permit,
        bytes calldata callData,
        bytes calldata signature
    ) external payable returns (bytes memory returnData);

    function isPermissioned(address owner, address operator, address target, bytes4 selector)
        external
        view
        returns (bool);

    function isAuthorizedCall(address owner, address operator, address target, bytes4 selector)
        external
        view
        returns (bool);

    function permissionNonce(address owner) external view returns (uint256);
    function executionNonce(address owner) external view returns (uint256);

    function activeExecutionOwner() external view returns (address);
    function activeExecutionOperator() external view returns (address);
    function activeExecutionTarget() external view returns (address);
    function activeExecutionSelector() external view returns (bytes4);
}

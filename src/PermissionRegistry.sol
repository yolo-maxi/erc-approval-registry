// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPermissionRegistry} from "./interfaces/IPermissionRegistry.sol";
import {EIP712} from "./utils/EIP712.sol";
import {ECDSA} from "./utils/ECDSA.sol";

/// @title PermissionRegistry
/// @notice Registry-first generic permission system scoped to (owner, operator, target, selector).
/// @dev Supports both persistent permission permits and one-off execution permits.
contract PermissionRegistry is IPermissionRegistry, EIP712 {
    using ECDSA for bytes32;

    bytes32 public constant PERMISSION_PERMIT_TYPEHASH = keccak256(
        "PermissionPermit(address owner,address operator,address target,bytes4 selector,bool approved,uint256 nonce,uint256 deadline)"
    );

    bytes32 public constant EXECUTION_PERMIT_TYPEHASH = keccak256(
        "ExecutionPermit(address owner,address operator,address target,bytes4 selector,bytes32 calldataHash,uint256 value,uint256 nonce,uint256 deadline)"
    );

    mapping(address owner => mapping(address operator => mapping(address target => mapping(bytes4 selector => bool approved))))
        private _permissions;

    mapping(address owner => uint256 nonce) public override permissionNonce;
    mapping(address owner => uint256 nonce) public override executionNonce;

    address private _activeExecutionOwner;
    address private _activeExecutionOperator;
    address private _activeExecutionTarget;
    bytes4 private _activeExecutionSelector;
    bool private _executing;

    constructor() EIP712("ERC-Permissions-Registry", "1") {}

    function grant(address operator, address target, bytes4 selector) external {
        _setPermission(msg.sender, operator, target, selector, true);
    }

    function revoke(address operator, address target, bytes4 selector) external {
        _setPermission(msg.sender, operator, target, selector, false);
    }

    function grantBatch(PermissionKey[] calldata keys) external {
        uint256 length = keys.length;
        for (uint256 i; i < length; ++i) {
            PermissionKey calldata key = keys[i];
            if (key.owner != msg.sender) revert PermissionDenied(key.owner, msg.sender, key.target, key.selector);
            _setPermission(key.owner, key.operator, key.target, key.selector, true);
        }
    }

    function revokeBatch(PermissionKey[] calldata keys) external {
        uint256 length = keys.length;
        for (uint256 i; i < length; ++i) {
            PermissionKey calldata key = keys[i];
            if (key.owner != msg.sender) revert PermissionDenied(key.owner, msg.sender, key.target, key.selector);
            _setPermission(key.owner, key.operator, key.target, key.selector, false);
        }
    }

    function permitPermission(PermissionPermit calldata permit, bytes calldata signature) external {
        if (block.timestamp > permit.deadline) revert DeadlineExpired();

        uint256 expectedNonce = permissionNonce[permit.owner];
        if (permit.nonce != expectedNonce) revert InvalidNonce(expectedNonce, permit.nonce);

        bytes32 structHash = keccak256(
            abi.encode(
                PERMISSION_PERMIT_TYPEHASH,
                permit.owner,
                permit.operator,
                permit.target,
                permit.selector,
                permit.approved,
                permit.nonce,
                permit.deadline
            )
        );

        address signer = _hashTypedDataV4(structHash).recover(signature);
        if (signer != permit.owner) revert InvalidSignature();

        unchecked {
            permissionNonce[permit.owner] = expectedNonce + 1;
        }

        _setPermission(permit.owner, permit.operator, permit.target, permit.selector, permit.approved);
    }

    function executeWithPermit(
        ExecutionPermit calldata permit,
        bytes calldata callData,
        bytes calldata signature
    ) external payable returns (bytes memory returnData) {
        if (block.timestamp > permit.deadline) revert DeadlineExpired();
        if (permit.target == address(0)) revert InvalidTarget();
        if (callData.length < 4) revert InvalidSelector();

        bytes4 callSelector = bytes4(callData);

        if (permit.selector != callSelector) revert InvalidSelector();
        if (permit.calldataHash != keccak256(callData)) revert InvalidCalldataHash();
        if (permit.value != msg.value) revert InvalidCalldataHash();

        uint256 expectedNonce = executionNonce[permit.owner];
        if (permit.nonce != expectedNonce) revert InvalidNonce(expectedNonce, permit.nonce);

        bytes32 structHash = keccak256(
            abi.encode(
                EXECUTION_PERMIT_TYPEHASH,
                permit.owner,
                permit.operator,
                permit.target,
                permit.selector,
                permit.calldataHash,
                permit.value,
                permit.nonce,
                permit.deadline
            )
        );

        address signer = _hashTypedDataV4(structHash).recover(signature);
        if (signer != permit.owner) revert InvalidSignature();
        if (msg.sender != permit.operator) revert PermissionDenied(permit.owner, msg.sender, permit.target, permit.selector);
        if (_executing) revert InvalidTarget();

        unchecked {
            executionNonce[permit.owner] = expectedNonce + 1;
        }

        _executing = true;
        _activeExecutionOwner = permit.owner;
        _activeExecutionOperator = permit.operator;
        _activeExecutionTarget = permit.target;
        _activeExecutionSelector = permit.selector;

        (bool ok, bytes memory data) = permit.target.call{value: msg.value}(callData);

        _executing = false;
        _activeExecutionOwner = address(0);
        _activeExecutionOperator = address(0);
        _activeExecutionTarget = address(0);
        _activeExecutionSelector = bytes4(0);

        if (!ok) revert CallFailed(data);

        emit ExecutionPermitUsed(
            permit.owner,
            permit.operator,
            permit.target,
            permit.selector,
            permit.calldataHash,
            permit.nonce
        );

        return data;
    }

    function isPermissioned(address owner, address operator, address target, bytes4 selector)
        external
        view
        returns (bool)
    {
        return _permissions[owner][operator][target][selector];
    }

    function isAuthorizedCall(address owner, address operator, address target, bytes4 selector)
        external
        view
        returns (bool)
    {
        if (_permissions[owner][operator][target][selector]) return true;

        return _executing
            && _activeExecutionOwner == owner
            && _activeExecutionOperator == operator
            && _activeExecutionTarget == target
            && _activeExecutionSelector == selector;
    }

    function activeExecutionOwner() external view returns (address) {
        return _activeExecutionOwner;
    }

    function activeExecutionOperator() external view returns (address) {
        return _activeExecutionOperator;
    }

    function activeExecutionTarget() external view returns (address) {
        return _activeExecutionTarget;
    }

    function activeExecutionSelector() external view returns (bytes4) {
        return _activeExecutionSelector;
    }

    function _setPermission(address owner, address operator, address target, bytes4 selector, bool approved) internal {
        if (owner == address(0) || operator == address(0) || target == address(0)) revert InvalidTarget();
        if (selector == bytes4(0)) revert InvalidSelector();

        _permissions[owner][operator][target][selector] = approved;
        emit PermissionSet(owner, operator, target, selector, approved);
    }
}

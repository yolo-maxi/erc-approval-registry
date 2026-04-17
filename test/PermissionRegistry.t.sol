// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "./Test.sol";
import {PermissionRegistry} from "src/PermissionRegistry.sol";
import {UniV3LPWrapper} from "src/examples/UniV3LPWrapper.sol";
import {UniV4LPWrapper} from "src/examples/UniV4LPWrapper.sol";
import {MockUniV3PositionManager} from "src/examples/MockUniV3PositionManager.sol";
import {MockUniV4PositionManager} from "src/examples/MockUniV4PositionManager.sol";
import {IPermissionRegistry} from "src/interfaces/IPermissionRegistry.sol";

contract PermissionRegistryTest is Test {
    PermissionRegistry internal registry;
    MockUniV3PositionManager internal v3Manager;
    MockUniV4PositionManager internal v4Manager;
    UniV3LPWrapper internal v3Wrapper;
    UniV4LPWrapper internal v4Wrapper;

    uint256 internal ownerPk = 0xA11CE;
    uint256 internal operatorPk = 0xB0B;
    address internal owner;
    address internal operator;
    address internal relayer;
    address internal stranger;

    function setUp() public {
        owner = vm.addr(ownerPk);
        operator = vm.addr(operatorPk);
        relayer = makeAddr("relayer");
        stranger = makeAddr("stranger");

        registry = new PermissionRegistry();
        v3Manager = new MockUniV3PositionManager();
        v4Manager = new MockUniV4PositionManager();
        v3Wrapper = new UniV3LPWrapper(address(registry), address(v3Manager));
        v4Wrapper = new UniV4LPWrapper(address(registry), address(v4Manager));
    }

    function testGrantAndRevokeDirectPermission() public {
        vm.prank(owner);
        registry.grant(operator, address(v3Wrapper), v3Wrapper.addLiquidity.selector);

        assertTrue(registry.isPermissioned(owner, operator, address(v3Wrapper), v3Wrapper.addLiquidity.selector));

        vm.prank(owner);
        registry.revoke(operator, address(v3Wrapper), v3Wrapper.addLiquidity.selector);

        assertFalse(registry.isPermissioned(owner, operator, address(v3Wrapper), v3Wrapper.addLiquidity.selector));
    }

    function testBatchGrantAndRevoke() public {
        IPermissionRegistry.PermissionKey[] memory keys = new IPermissionRegistry.PermissionKey[](2);
        keys[0] = IPermissionRegistry.PermissionKey({
            owner: owner,
            operator: operator,
            target: address(v3Wrapper),
            selector: v3Wrapper.openManagedPosition.selector
        });
        keys[1] = IPermissionRegistry.PermissionKey({
            owner: owner,
            operator: operator,
            target: address(v3Wrapper),
            selector: v3Wrapper.collectFees.selector
        });

        vm.prank(owner);
        registry.grantBatch(keys);

        assertTrue(registry.isPermissioned(owner, operator, address(v3Wrapper), v3Wrapper.openManagedPosition.selector));
        assertTrue(registry.isPermissioned(owner, operator, address(v3Wrapper), v3Wrapper.collectFees.selector));

        vm.prank(owner);
        registry.revokeBatch(keys);

        assertFalse(registry.isPermissioned(owner, operator, address(v3Wrapper), v3Wrapper.openManagedPosition.selector));
        assertFalse(registry.isPermissioned(owner, operator, address(v3Wrapper), v3Wrapper.collectFees.selector));
    }

    function testPermissionPermitGrantAndUse() public {
        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            owner: owner,
            operator: operator,
            target: address(v3Wrapper),
            selector: v3Wrapper.openManagedPosition.selector,
            approved: true,
            nonce: 0,
            deadline: block.timestamp + 1 days
        });

        bytes memory sig = _signPermissionPermit(permit, ownerPk);
        vm.prank(relayer);
        registry.permitPermission(permit, sig);

        vm.prank(operator);
        (uint256 managedId, uint256 tokenId) = v3Wrapper.openManagedPosition(owner, -60, 60, 1_000);

        assertEq(managedId, 1);
        assertEq(tokenId, 1);
        (address storedOwner, uint256 storedTokenId) = v3Wrapper.managedPositions(managedId);
        assertEq(storedOwner, owner);
        assertEq(storedTokenId, tokenId);
    }

    function testExecutionPermitAllowsOneOffOpenPosition() public {
        bytes memory callData = abi.encodeCall(v3Wrapper.openManagedPosition, (owner, -120, 120, 5_000));
        IPermissionRegistry.ExecutionPermit memory permit = IPermissionRegistry.ExecutionPermit({
            owner: owner,
            operator: operator,
            target: address(v3Wrapper),
            selector: v3Wrapper.openManagedPosition.selector,
            calldataHash: keccak256(callData),
            value: 0,
            nonce: 0,
            deadline: block.timestamp + 1 days
        });

        bytes memory sig = _signExecutionPermit(permit, ownerPk);
        vm.prank(operator);
        bytes memory returnData = registry.executeWithPermit(permit, callData, sig);
        (uint256 managedId, uint256 tokenId) = abi.decode(returnData, (uint256, uint256));

        assertEq(managedId, 1);
        assertEq(tokenId, 1);
        (address storedOwner, uint256 storedTokenId) = v3Wrapper.managedPositions(1);
        assertEq(storedOwner, owner);
        assertEq(storedTokenId, tokenId);
    }

    function testExecutionPermitCannotBeReplayed() public {
        bytes memory callData = abi.encodeCall(v3Wrapper.openManagedPosition, (owner, -10, 10, 123));
        IPermissionRegistry.ExecutionPermit memory permit = IPermissionRegistry.ExecutionPermit({
            owner: owner,
            operator: operator,
            target: address(v3Wrapper),
            selector: v3Wrapper.openManagedPosition.selector,
            calldataHash: keccak256(callData),
            value: 0,
            nonce: 0,
            deadline: block.timestamp + 1 days
        });

        bytes memory sig = _signExecutionPermit(permit, ownerPk);
        vm.prank(operator);
        registry.executeWithPermit(permit, callData, sig);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IPermissionRegistry.InvalidNonce.selector, 1, 0));
        registry.executeWithPermit(permit, callData, sig);
    }

    function testWrongOperatorCannotUseExecutionPermit() public {
        bytes memory callData = abi.encodeCall(v3Wrapper.openManagedPosition, (owner, -10, 10, 123));
        IPermissionRegistry.ExecutionPermit memory permit = IPermissionRegistry.ExecutionPermit({
            owner: owner,
            operator: operator,
            target: address(v3Wrapper),
            selector: v3Wrapper.openManagedPosition.selector,
            calldataHash: keccak256(callData),
            value: 0,
            nonce: 0,
            deadline: block.timestamp + 1 days
        });

        bytes memory sig = _signExecutionPermit(permit, ownerPk);
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPermissionRegistry.PermissionDenied.selector,
                owner,
                stranger,
                address(v3Wrapper),
                v3Wrapper.openManagedPosition.selector
            )
        );
        registry.executeWithPermit(permit, callData, sig);
    }

    function testInvalidCalldataHashReverts() public {
        bytes memory callData = abi.encodeCall(v3Wrapper.openManagedPosition, (owner, -10, 10, 123));
        IPermissionRegistry.ExecutionPermit memory permit = IPermissionRegistry.ExecutionPermit({
            owner: owner,
            operator: operator,
            target: address(v3Wrapper),
            selector: v3Wrapper.openManagedPosition.selector,
            calldataHash: keccak256("wrong"),
            value: 0,
            nonce: 0,
            deadline: block.timestamp + 1 days
        });

        bytes memory sig = _signExecutionPermit(permit, ownerPk);
        vm.prank(operator);
        vm.expectRevert(IPermissionRegistry.InvalidCalldataHash.selector);
        registry.executeWithPermit(permit, callData, sig);
    }

    function testDirectUnauthorizedCallReverts() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPermissionRegistry.PermissionDenied.selector,
                owner,
                stranger,
                address(v3Wrapper),
                v3Wrapper.openManagedPosition.selector
            )
        );
        v3Wrapper.openManagedPosition(owner, -1, 1, 100);
    }

    function testPersistentPermissionEnablesLifecycleOnV3Wrapper() public {
        IPermissionRegistry.PermissionKey[] memory keys = new IPermissionRegistry.PermissionKey[](3);
        keys[0] = IPermissionRegistry.PermissionKey(owner, operator, address(v3Wrapper), v3Wrapper.openManagedPosition.selector);
        keys[1] = IPermissionRegistry.PermissionKey(owner, operator, address(v3Wrapper), v3Wrapper.addLiquidity.selector);
        keys[2] = IPermissionRegistry.PermissionKey(owner, operator, address(v3Wrapper), v3Wrapper.collectFees.selector);

        vm.prank(owner);
        registry.grantBatch(keys);

        vm.prank(operator);
        (uint256 managedId, uint256 tokenId) = v3Wrapper.openManagedPosition(owner, -100, 100, 2_000);

        vm.prank(operator);
        v3Wrapper.addLiquidity(managedId, 250);
        (, , , uint128 liquidityAfter, , ) = v3Manager.positions(tokenId);
        assertEq(uint256(liquidityAfter), 2_250);

        v3Manager.seedFees(tokenId, 7 ether, 11 ether);
        vm.prank(operator);
        (uint256 amount0, uint256 amount1) = v3Wrapper.collectFees(managedId, operator);
        assertEq(amount0, 7 ether);
        assertEq(amount1, 11 ether);
    }

    function testExecutionPermitWorksForV4RebalanceFlow() public {
        vm.startPrank(owner);
        (uint256 managedId, uint256 positionId) = v4Wrapper.openManagedPosition(owner, keccak256("pool"), -50, 50, 1_000);
        vm.stopPrank();

        bytes memory callData = abi.encodeCall(v4Wrapper.rebalance, (managedId, int128(300)));
        IPermissionRegistry.ExecutionPermit memory permit = IPermissionRegistry.ExecutionPermit({
            owner: owner,
            operator: operator,
            target: address(v4Wrapper),
            selector: v4Wrapper.rebalance.selector,
            calldataHash: keccak256(callData),
            value: 0,
            nonce: 0,
            deadline: block.timestamp + 1 days
        });

        bytes memory sig = _signExecutionPermit(permit, ownerPk);
        vm.prank(operator);
        registry.executeWithPermit(permit, callData, sig);

        (, , , , uint128 liquidityAfter, , ) = v4Manager.positions(positionId);
        assertEq(uint256(liquidityAfter), 1_300);
    }

    function _signPermissionPermit(IPermissionRegistry.PermissionPermit memory permit, uint256 pk)
        internal
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                registry.PERMISSION_PERMIT_TYPEHASH(),
                permit.owner,
                permit.operator,
                permit.target,
                permit.selector,
                permit.approved,
                permit.nonce,
                permit.deadline
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", registry.DOMAIN_SEPARATOR(), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signExecutionPermit(IPermissionRegistry.ExecutionPermit memory permit, uint256 pk)
        internal
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                registry.EXECUTION_PERMIT_TYPEHASH(),
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
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", registry.DOMAIN_SEPARATOR(), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }
}

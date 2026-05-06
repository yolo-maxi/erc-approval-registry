// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "./Test.sol";
import {PermissionRegistry} from "src/PermissionRegistry.sol";
import {IPermissionRegistry} from "src/interfaces/IPermissionRegistry.sol";
import {MockUniV3PositionManager} from "src/examples/MockUniV3PositionManager.sol";
import {UniV3LPWrapper} from "src/examples/UniV3LPWrapper.sol";
import {MockStakingRewardsManager} from "src/examples/MockStakingRewardsManager.sol";
import {StakingRewardsWrapper} from "src/examples/StakingRewardsWrapper.sol";
import {SimpleTreasury} from "src/examples/SimpleTreasury.sol";

contract PermissionRegistryTest is Test {
    PermissionRegistry internal registry;
    MockUniV3PositionManager internal lpManager;
    UniV3LPWrapper internal lpWrapper;
    MockStakingRewardsManager internal stakingManager;
    StakingRewardsWrapper internal stakingWrapper;
    SimpleTreasury internal treasury;

    address internal owner;
    address internal operator;
    address internal stranger;
    address internal recipient;

    function setUp() public {
        owner = makeAddr("owner");
        operator = makeAddr("operator");
        stranger = makeAddr("stranger");
        recipient = makeAddr("recipient");

        registry = new PermissionRegistry();

        lpManager = new MockUniV3PositionManager();
        lpWrapper = new UniV3LPWrapper(address(registry), address(lpManager));

        stakingManager = new MockStakingRewardsManager();
        stakingWrapper = new StakingRewardsWrapper(address(registry), address(stakingManager));

        treasury = new SimpleTreasury(address(registry));
    }

    function testOwnerCanOpenPositionWithoutRegistryPermission() public {
        vm.prank(owner);
        (uint256 managedId, uint256 tokenId) = lpWrapper.openManagedPosition(owner, -60, 60, 1_000);

        assertEq(managedId, 1);
        assertEq(tokenId, 1);

        (address storedOwner, uint256 storedTokenId) = lpWrapper.managedPositions(managedId);
        assertEq(storedOwner, owner);
        assertEq(storedTokenId, tokenId);
    }

    function testLpClaimCanBeAuthorizedWithoutTransferRights() public {
        uint256 managedId = _openLpPositionForOwner();
        uint256 tokenId = 1;

        vm.prank(owner);
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);

        lpManager.seedFees(tokenId, 3 ether, 5 ether);

        vm.prank(operator);
        (uint256 amount0, uint256 amount1) = lpWrapper.claim(managedId, recipient);

        assertEq(amount0, 3 ether);
        assertEq(amount1, 5 ether);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPermissionRegistry.PermissionDenied.selector,
                owner,
                operator,
                address(lpWrapper),
                lpWrapper.transferManagedPosition.selector
            )
        );
        lpWrapper.transferManagedPosition(managedId, stranger);
    }

    function testBatchGrantLetsOperatorHandleMultipleLpFunctions() public {
        uint256 managedId = _openLpPositionForOwner();

        IPermissionRegistry.PermissionKey[] memory keys = new IPermissionRegistry.PermissionKey[](2);
        keys[0] = IPermissionRegistry.PermissionKey(owner, operator, address(lpWrapper), lpWrapper.addLiquidity.selector);
        keys[1] = IPermissionRegistry.PermissionKey(owner, operator, address(lpWrapper), lpWrapper.claim.selector);

        vm.prank(owner);
        registry.grantBatch(keys);

        vm.prank(operator);
        lpWrapper.addLiquidity(managedId, 250);

        (, , , uint128 liquidity, , ) = lpManager.positions(1);
        assertEq(uint256(liquidity), 1_250);

        lpManager.seedFees(1, 9 ether, 4 ether);

        vm.prank(operator);
        (uint256 amount0, uint256 amount1) = lpWrapper.claim(managedId, recipient);

        assertEq(amount0, 9 ether);
        assertEq(amount1, 4 ether);
    }

    function testRevokeTurnsPermissionOff() public {
        uint256 managedId = _openLpPositionForOwner();

        vm.startPrank(owner);
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);
        registry.revoke(operator, address(lpWrapper), lpWrapper.claim.selector);
        vm.stopPrank();

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPermissionRegistry.PermissionDenied.selector,
                owner,
                operator,
                address(lpWrapper),
                lpWrapper.claim.selector
            )
        );
        lpWrapper.claim(managedId, recipient);
    }

    function testPermissionIsScopedToTarget() public {
        vm.prank(owner);
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);

        assertTrue(registry.isAuthorizedCall(owner, operator, address(lpWrapper), lpWrapper.claim.selector));
        assertFalse(registry.isAuthorizedCall(owner, operator, address(lpManager), lpWrapper.claim.selector));
    }

    function testStakingRewardsCanBeClaimedWithoutUnstakeRights() public {
        uint256 managedId = _openStakeForOwner();
        uint256 positionId = 1;

        vm.prank(owner);
        registry.grant(operator, address(stakingWrapper), stakingWrapper.claimRewards.selector);

        stakingManager.seedRewards(positionId, 42 ether);

        vm.prank(operator);
        uint256 claimed = stakingWrapper.claimRewards(managedId, recipient);
        assertEq(claimed, 42 ether);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPermissionRegistry.PermissionDenied.selector,
                owner,
                operator,
                address(stakingWrapper),
                stakingWrapper.unstake.selector
            )
        );
        stakingWrapper.unstake(managedId, 100);
    }

    function testTreasuryCanAuthorizeRebalanceWithoutControlTransfer() public {
        vm.prank(owner);
        registry.grant(operator, address(treasury), treasury.rebalance.selector);

        vm.prank(operator);
        treasury.rebalance(owner);
        assertEq(treasury.rebalances(owner), 1);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPermissionRegistry.PermissionDenied.selector,
                owner,
                operator,
                address(treasury),
                treasury.transferTreasuryControl.selector
            )
        );
        treasury.transferTreasuryControl(owner, stranger);
    }

    // -------------------------------------------------------------------------
    // Expiry tests
    // -------------------------------------------------------------------------

    function testGrantWithExpiryWorksBeforeExpiry() public {
        uint256 managedId = _openLpPositionForOwner();
        uint48 expiry = uint48(block.timestamp + 1 days);

        vm.prank(owner);
        registry.grantWithExpiry(operator, address(lpWrapper), lpWrapper.claim.selector, expiry);

        assertTrue(registry.isAuthorizedCall(owner, operator, address(lpWrapper), lpWrapper.claim.selector));
        assertEq(registry.permissionExpiry(owner, operator, address(lpWrapper), lpWrapper.claim.selector), expiry);

        lpManager.seedFees(1, 1 ether, 2 ether);
        vm.prank(operator);
        (uint256 a0, uint256 a1) = lpWrapper.claim(managedId, recipient);
        assertEq(a0, 1 ether);
        assertEq(a1, 2 ether);
    }

    function testGrantWithExpiryRevertsAfterExpiry() public {
        uint256 managedId = _openLpPositionForOwner();
        uint48 expiry = uint48(block.timestamp + 1 days);

        vm.prank(owner);
        registry.grantWithExpiry(operator, address(lpWrapper), lpWrapper.claim.selector, expiry);

        vm.warp(block.timestamp + 1 days + 1);

        assertFalse(registry.isAuthorizedCall(owner, operator, address(lpWrapper), lpWrapper.claim.selector));

        lpManager.seedFees(1, 1 ether, 2 ether);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPermissionRegistry.PermissionExpired.selector,
                owner,
                operator,
                address(lpWrapper),
                lpWrapper.claim.selector
            )
        );
        lpWrapper.claim(managedId, recipient);
    }

    function testGrantPermanentIsUnaffectedByTime() public {
        uint256 managedId = _openLpPositionForOwner();

        vm.prank(owner);
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);

        vm.warp(block.timestamp + 365 days * 100);

        assertTrue(registry.isAuthorizedCall(owner, operator, address(lpWrapper), lpWrapper.claim.selector));

        lpManager.seedFees(1, 7 ether, 3 ether);
        vm.prank(operator);
        (uint256 a0, uint256 a1) = lpWrapper.claim(managedId, recipient);
        assertEq(a0, 7 ether);
        assertEq(a1, 3 ether);
    }

    // -------------------------------------------------------------------------
    // PermissionPermit tests
    // -------------------------------------------------------------------------

    function testPermitPermissionGrantsOnBehalfOfOwner() public {
        uint256 ownerKey = 0xA11CE;
        address ownerAddr = vm.addr(ownerKey);

        uint256 managedId = _openLpPositionAs(ownerAddr);

        uint256 deadline = block.timestamp + 1 hours;
        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            owner: ownerAddr,
            operator: operator,
            target: address(lpWrapper),
            selector: lpWrapper.claim.selector,
            expiry: type(uint48).max,
            nonce: 0,
            deadline: deadline
        });

        bytes32 structHash = keccak256(
            abi.encode(
                registry.PERMISSION_PERMIT_TYPEHASH(),
                permit.owner,
                permit.operator,
                permit.target,
                permit.selector,
                permit.expiry,
                permit.nonce,
                permit.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", registry.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        registry.permitPermission(permit, sig);

        assertTrue(registry.isAuthorizedCall(ownerAddr, operator, address(lpWrapper), lpWrapper.claim.selector));
        assertEq(registry.permissionNonce(ownerAddr), 1);

        lpManager.seedFees(1, 5 ether, 0);
        vm.prank(operator);
        (uint256 a0,) = lpWrapper.claim(managedId, recipient);
        assertEq(a0, 5 ether);
    }

    function testPermitPermissionRevokeOnBehalfOfOwner() public {
        uint256 ownerKey = 0xA11CE;
        address ownerAddr = vm.addr(ownerKey);

        vm.prank(ownerAddr);
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);
        assertTrue(registry.isAuthorizedCall(ownerAddr, operator, address(lpWrapper), lpWrapper.claim.selector));

        uint256 deadline = block.timestamp + 1 hours;
        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            owner: ownerAddr,
            operator: operator,
            target: address(lpWrapper),
            selector: lpWrapper.claim.selector,
            expiry: 0, // revoke
            nonce: 0,
            deadline: deadline
        });

        bytes32 structHash = keccak256(
            abi.encode(
                registry.PERMISSION_PERMIT_TYPEHASH(),
                permit.owner,
                permit.operator,
                permit.target,
                permit.selector,
                permit.expiry,
                permit.nonce,
                permit.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", registry.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);

        registry.permitPermission(permit, abi.encodePacked(r, s, v));

        assertFalse(registry.isAuthorizedCall(ownerAddr, operator, address(lpWrapper), lpWrapper.claim.selector));
    }

    function testPermitPermissionRejectsWrongSigner() public {
        uint256 ownerKey = 0xA11CE;
        uint256 wrongKey = 0xBAD;
        address ownerAddr = vm.addr(ownerKey);

        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            owner: ownerAddr,
            operator: operator,
            target: address(lpWrapper),
            selector: lpWrapper.claim.selector,
            expiry: type(uint48).max,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        bytes32 structHash = keccak256(
            abi.encode(
                registry.PERMISSION_PERMIT_TYPEHASH(),
                permit.owner,
                permit.operator,
                permit.target,
                permit.selector,
                permit.expiry,
                permit.nonce,
                permit.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", registry.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, digest);

        vm.expectRevert(IPermissionRegistry.InvalidSignature.selector);
        registry.permitPermission(permit, abi.encodePacked(r, s, v));
    }

    function testPermitPermissionRejectsExpiredDeadline() public {
        uint256 ownerKey = 0xA11CE;
        address ownerAddr = vm.addr(ownerKey);

        uint256 deadline = block.timestamp - 1;
        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            owner: ownerAddr,
            operator: operator,
            target: address(lpWrapper),
            selector: lpWrapper.claim.selector,
            expiry: type(uint48).max,
            nonce: 0,
            deadline: deadline
        });

        bytes32 structHash = keccak256(
            abi.encode(
                registry.PERMISSION_PERMIT_TYPEHASH(),
                permit.owner,
                permit.operator,
                permit.target,
                permit.selector,
                permit.expiry,
                permit.nonce,
                permit.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", registry.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);

        vm.expectRevert(IPermissionRegistry.DeadlineExpired.selector);
        registry.permitPermission(permit, abi.encodePacked(r, s, v));
    }

    function testPermitPermissionRejectsReplay() public {
        uint256 ownerKey = 0xA11CE;
        address ownerAddr = vm.addr(ownerKey);

        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            owner: ownerAddr,
            operator: operator,
            target: address(lpWrapper),
            selector: lpWrapper.claim.selector,
            expiry: type(uint48).max,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        bytes32 structHash = keccak256(
            abi.encode(
                registry.PERMISSION_PERMIT_TYPEHASH(),
                permit.owner,
                permit.operator,
                permit.target,
                permit.selector,
                permit.expiry,
                permit.nonce,
                permit.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", registry.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        registry.permitPermission(permit, sig);

        vm.expectRevert(abi.encodeWithSelector(IPermissionRegistry.InvalidNonce.selector, uint256(1), uint256(0)));
        registry.permitPermission(permit, sig);
    }

    // -------------------------------------------------------------------------
    // Expiry boundary conditions
    // -------------------------------------------------------------------------

    function testExpiryIsInclusiveAtBoundaryTimestamp() public {
        // At exactly the expiry timestamp the permission should still be valid.
        uint48 expiry = uint48(block.timestamp + 1 days);

        vm.prank(owner);
        registry.grantWithExpiry(operator, address(lpWrapper), lpWrapper.claim.selector, expiry);

        vm.warp(expiry); // exactly at expiry

        assertTrue(registry.isAuthorizedCall(owner, operator, address(lpWrapper), lpWrapper.claim.selector));
    }

    function testExpiryIsExpiredOneSecondAfterBoundary() public {
        uint48 expiry = uint48(block.timestamp + 1 days);

        vm.prank(owner);
        registry.grantWithExpiry(operator, address(lpWrapper), lpWrapper.claim.selector, expiry);

        vm.warp(expiry + 1);

        assertFalse(registry.isAuthorizedCall(owner, operator, address(lpWrapper), lpWrapper.claim.selector));
    }

    function testGrantWithExpiryAtCurrentTimestampReverts() public {
        uint48 now_ = uint48(block.timestamp);
        vm.prank(owner);
        vm.expectRevert(IPermissionRegistry.InvalidExpiry.selector);
        registry.grantWithExpiry(operator, address(lpWrapper), lpWrapper.claim.selector, now_);
    }

    // -------------------------------------------------------------------------
    // Expiry overwrite semantics
    // -------------------------------------------------------------------------

    function testGrantOverwritesExpiryWithPermanent() public {
        uint256 managedId = _openLpPositionForOwner();
        uint48 expiry = uint48(block.timestamp + 1 days);

        vm.startPrank(owner);
        registry.grantWithExpiry(operator, address(lpWrapper), lpWrapper.claim.selector, expiry);
        // Overwrite with a permanent grant before it expires.
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);
        vm.stopPrank();

        vm.warp(expiry + 1); // past the original expiry

        assertTrue(registry.isAuthorizedCall(owner, operator, address(lpWrapper), lpWrapper.claim.selector));

        lpManager.seedFees(1, 1 ether, 0);
        vm.prank(operator);
        lpWrapper.claim(managedId, recipient);
    }

    function testGrantWithExpiryOverwritesPermanentGrant() public {
        uint256 managedId = _openLpPositionForOwner();
        uint48 expiry = uint48(block.timestamp + 1 days);

        vm.startPrank(owner);
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);
        // Downgrade to a time-bounded permission.
        registry.grantWithExpiry(operator, address(lpWrapper), lpWrapper.claim.selector, expiry);
        vm.stopPrank();

        vm.warp(expiry + 1);

        assertFalse(registry.isAuthorizedCall(owner, operator, address(lpWrapper), lpWrapper.claim.selector));

        lpManager.seedFees(1, 1 ether, 0);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPermissionRegistry.PermissionExpired.selector,
                owner, operator, address(lpWrapper), lpWrapper.claim.selector
            )
        );
        lpWrapper.claim(managedId, recipient);
    }

    // -------------------------------------------------------------------------
    // Permission space isolation
    // -------------------------------------------------------------------------

    function testStrangerRevokeCannotTouchOwnerPermission() public {
        // The owner is the primary key in the permission mapping.
        // A stranger calling revoke() can only zero out their OWN (stranger → operator) slot.
        uint256 managedId = _openLpPositionForOwner();

        vm.prank(owner);
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);

        // Stranger tries to revoke the owner's grant — this only writes to
        // permissions[stranger][operator][...] which was never set.
        vm.prank(stranger);
        registry.revoke(operator, address(lpWrapper), lpWrapper.claim.selector);

        // Owner's permission is untouched.
        assertTrue(registry.isAuthorizedCall(owner, operator, address(lpWrapper), lpWrapper.claim.selector));

        lpManager.seedFees(1, 1 ether, 0);
        vm.prank(operator);
        lpWrapper.claim(managedId, recipient);
    }

    function testOperatorCannotRevokeTheirOwnIncomingGrant() public {
        // Operator calls revoke(owner, target, selector) which writes to
        // permissions[operator][owner][target][selector] — the slot where
        // operator would be the *owner*, not their incoming permission.
        uint256 managedId = _openLpPositionForOwner();

        vm.prank(owner);
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);

        // Operator tries to self-revoke.
        vm.prank(operator);
        registry.revoke(owner, address(lpWrapper), lpWrapper.claim.selector);

        // The grant from owner→operator is still intact.
        assertTrue(registry.isAuthorizedCall(owner, operator, address(lpWrapper), lpWrapper.claim.selector));

        lpManager.seedFees(1, 1 ether, 0);
        vm.prank(operator);
        lpWrapper.claim(managedId, recipient);
    }

    function testTwoOwnersGrantingToSameOperatorAreIndependent() public {
        address ownerB = makeAddr("ownerB");

        vm.prank(owner);
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);

        vm.prank(ownerB);
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);

        // Owner A revokes — owner B's grant must survive.
        vm.prank(owner);
        registry.revoke(operator, address(lpWrapper), lpWrapper.claim.selector);

        assertFalse(registry.isAuthorizedCall(owner, operator, address(lpWrapper), lpWrapper.claim.selector));
        assertTrue(registry.isAuthorizedCall(ownerB, operator, address(lpWrapper), lpWrapper.claim.selector));
    }

    // -------------------------------------------------------------------------
    // Batch atomicity
    // -------------------------------------------------------------------------

    function testBatchGrantIsAtomicOnOwnerMismatch() public {
        address ownerB = makeAddr("ownerB");

        IPermissionRegistry.PermissionKey[] memory keys = new IPermissionRegistry.PermissionKey[](3);
        keys[0] = IPermissionRegistry.PermissionKey(owner, operator, address(lpWrapper), lpWrapper.claim.selector);
        keys[1] = IPermissionRegistry.PermissionKey(ownerB, operator, address(lpWrapper), lpWrapper.addLiquidity.selector); // wrong owner
        keys[2] = IPermissionRegistry.PermissionKey(owner, operator, address(lpWrapper), lpWrapper.addLiquidity.selector);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPermissionRegistry.PermissionDenied.selector,
                ownerB, owner, address(lpWrapper), lpWrapper.addLiquidity.selector
            )
        );
        registry.grantBatch(keys);

        // No partial state — keys[0] must not have been set.
        assertFalse(registry.isAuthorizedCall(owner, operator, address(lpWrapper), lpWrapper.claim.selector));
        assertFalse(registry.isAuthorizedCall(owner, operator, address(lpWrapper), lpWrapper.addLiquidity.selector));
    }

    // -------------------------------------------------------------------------
    // Input validation
    // -------------------------------------------------------------------------

    function testGrantRevertsOnZeroOperator() public {
        vm.prank(owner);
        vm.expectRevert(IPermissionRegistry.InvalidAddress.selector);
        registry.grant(address(0), address(lpWrapper), lpWrapper.claim.selector);
    }

    function testGrantRevertsOnZeroTarget() public {
        vm.prank(owner);
        vm.expectRevert(IPermissionRegistry.InvalidAddress.selector);
        registry.grant(operator, address(0), lpWrapper.claim.selector);
    }

    function testGrantRevertsOnZeroSelector() public {
        vm.prank(owner);
        vm.expectRevert(IPermissionRegistry.InvalidSelector.selector);
        registry.grant(operator, address(lpWrapper), bytes4(0));
    }

    function testRevokeNonexistentPermissionDoesNotRevert() public {
        // Revoke on a slot that was never set should silently succeed.
        vm.prank(owner);
        registry.revoke(operator, address(lpWrapper), lpWrapper.claim.selector);

        assertFalse(registry.isAuthorizedCall(owner, operator, address(lpWrapper), lpWrapper.claim.selector));
    }

    function testSelfGrantOwnerAsOperator() public {
        // An owner granting themselves is unusual but not disallowed.
        uint256 managedId = _openLpPositionForOwner();

        vm.prank(owner);
        registry.grant(owner, address(lpWrapper), lpWrapper.claim.selector);

        assertTrue(registry.isAuthorizedCall(owner, owner, address(lpWrapper), lpWrapper.claim.selector));

        lpManager.seedFees(1, 2 ether, 1 ether);
        // Owner calling directly still works (short-circuits registry check).
        vm.prank(owner);
        lpWrapper.claim(managedId, recipient);
    }

    // -------------------------------------------------------------------------
    // Permit edge cases
    // -------------------------------------------------------------------------

    function testPermitWithSkippedNonceReverts() public {
        uint256 ownerKey = 0xA11CE;
        address ownerAddr = vm.addr(ownerKey);

        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            owner: ownerAddr,
            operator: operator,
            target: address(lpWrapper),
            selector: lpWrapper.claim.selector,
            expiry: type(uint48).max,
            nonce: 5, // current nonce is 0
            deadline: block.timestamp + 1 hours
        });

        bytes memory sig = _signPermit(ownerKey, permit);
        vm.expectRevert(abi.encodeWithSelector(IPermissionRegistry.InvalidNonce.selector, uint256(0), uint256(5)));
        registry.permitPermission(permit, sig);
    }

    function testPermitDeadlineAtCurrentTimestampIsValid() public {
        // Deadline check is strict: reverts only when block.timestamp > deadline.
        // deadline == block.timestamp should pass.
        uint256 ownerKey = 0xA11CE;
        address ownerAddr = vm.addr(ownerKey);

        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            owner: ownerAddr,
            operator: operator,
            target: address(lpWrapper),
            selector: lpWrapper.claim.selector,
            expiry: type(uint48).max,
            nonce: 0,
            deadline: block.timestamp // exactly now
        });

        registry.permitPermission(permit, _signPermit(ownerKey, permit));

        assertTrue(registry.isAuthorizedCall(ownerAddr, operator, address(lpWrapper), lpWrapper.claim.selector));
    }

    function testPermitGrantedPermissionCanBeRevokedDirectly() public {
        uint256 ownerKey = 0xA11CE;
        address ownerAddr = vm.addr(ownerKey);

        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            owner: ownerAddr,
            operator: operator,
            target: address(lpWrapper),
            selector: lpWrapper.claim.selector,
            expiry: type(uint48).max,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        registry.permitPermission(permit, _signPermit(ownerKey, permit));
        assertTrue(registry.isAuthorizedCall(ownerAddr, operator, address(lpWrapper), lpWrapper.claim.selector));

        // Owner revokes the permit-granted permission directly.
        vm.prank(ownerAddr);
        registry.revoke(operator, address(lpWrapper), lpWrapper.claim.selector);

        assertFalse(registry.isAuthorizedCall(ownerAddr, operator, address(lpWrapper), lpWrapper.claim.selector));
    }

    function testPermitCanGrantTimeBoundedPermission() public {
        uint256 ownerKey = 0xA11CE;
        address ownerAddr = vm.addr(ownerKey);
        uint48 expiry = uint48(block.timestamp + 7 days);

        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            owner: ownerAddr,
            operator: operator,
            target: address(lpWrapper),
            selector: lpWrapper.claim.selector,
            expiry: expiry,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        registry.permitPermission(permit, _signPermit(ownerKey, permit));

        assertEq(registry.permissionExpiry(ownerAddr, operator, address(lpWrapper), lpWrapper.claim.selector), expiry);

        vm.warp(expiry + 1);
        assertFalse(registry.isAuthorizedCall(ownerAddr, operator, address(lpWrapper), lpWrapper.claim.selector));
    }

    function testPermitWithAlreadyExpiredExpiryReverts() public {
        uint256 ownerKey = 0xA11CE;
        address ownerAddr = vm.addr(ownerKey);

        vm.warp(1_000_000);

        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            owner: ownerAddr,
            operator: operator,
            target: address(lpWrapper),
            selector: lpWrapper.claim.selector,
            expiry: uint48(block.timestamp - 1), // already expired
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        bytes memory sig = _signPermit(ownerKey, permit);
        vm.expectRevert(IPermissionRegistry.InvalidExpiry.selector);
        registry.permitPermission(permit, sig);
    }

    // -------------------------------------------------------------------------
    // Signature security
    // -------------------------------------------------------------------------

    function testHighSSignatureIsRejected() public {
        // A malleable (high-s) twin of a valid signature must be rejected.
        uint256 ownerKey = 0xA11CE;
        address ownerAddr = vm.addr(ownerKey);

        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            owner: ownerAddr,
            operator: operator,
            target: address(lpWrapper),
            selector: lpWrapper.claim.selector,
            expiry: type(uint48).max,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        bytes32 structHash = keccak256(
            abi.encode(
                registry.PERMISSION_PERMIT_TYPEHASH(),
                permit.owner, permit.operator, permit.target,
                permit.selector, permit.expiry, permit.nonce, permit.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", registry.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);

        // Compute malleable twin: s' = n - s, v' flipped.
        uint256 secp256k1n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        bytes32 sHigh = bytes32(secp256k1n - uint256(s));
        uint8 vHigh = v == 27 ? 28 : 27;

        vm.expectRevert(bytes4(keccak256("InvalidSignature()")));
        registry.permitPermission(permit, abi.encodePacked(r, sHigh, vHigh));
    }

    function testPermitOperatorMutationInvalidatesSignature() public {
        // Altering any struct field after signing must cause an InvalidSignature revert,
        // proving that all fields are committed in the EIP-712 hash.
        uint256 ownerKey = 0xA11CE;
        address ownerAddr = vm.addr(ownerKey);

        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            owner: ownerAddr,
            operator: operator,
            target: address(lpWrapper),
            selector: lpWrapper.claim.selector,
            expiry: type(uint48).max,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        bytes memory sig = _signPermit(ownerKey, permit);

        // Swap in a different operator after signing.
        permit.operator = stranger;

        vm.expectRevert(IPermissionRegistry.InvalidSignature.selector);
        registry.permitPermission(permit, sig);
    }

    function testPermitExpiryMutationInvalidatesSignature() public {
        uint256 ownerKey = 0xA11CE;
        address ownerAddr = vm.addr(ownerKey);

        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            owner: ownerAddr,
            operator: operator,
            target: address(lpWrapper),
            selector: lpWrapper.claim.selector,
            expiry: uint48(block.timestamp + 7 days),
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        bytes memory sig = _signPermit(ownerKey, permit);

        // Inflate the expiry after signing.
        permit.expiry = type(uint48).max;

        vm.expectRevert(IPermissionRegistry.InvalidSignature.selector);
        registry.permitPermission(permit, sig);
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _signPermit(uint256 privateKey, IPermissionRegistry.PermissionPermit memory permit)
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
                permit.expiry,
                permit.nonce,
                permit.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", registry.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _openLpPositionForOwner() internal returns (uint256 managedId) {
        vm.prank(owner);
        (managedId,) = lpWrapper.openManagedPosition(owner, -60, 60, 1_000);
    }

    function _openLpPositionAs(address ownerAddr) internal returns (uint256 managedId) {
        vm.prank(ownerAddr);
        (managedId,) = lpWrapper.openManagedPosition(ownerAddr, -60, 60, 1_000);
    }

    function _openStakeForOwner() internal returns (uint256 managedId) {
        vm.prank(owner);
        (managedId,) = stakingWrapper.openManagedStake(owner, 1_000);
    }
}

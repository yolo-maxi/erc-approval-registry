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

    address internal user;
    address internal operator;
    address internal stranger;
    address internal recipient;

    function setUp() public {
        user = makeAddr("user");
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

    function testUserCanOpenPositionWithoutRegistryPermission() public {
        vm.prank(user);
        (uint256 managedId, uint256 tokenId) = lpWrapper.openManagedPosition(user, -60, 60, 1_000);

        assertEq(managedId, 1);
        assertEq(tokenId, 1);

        (address storedUser, uint256 storedTokenId) = lpWrapper.managedPositions(managedId);
        assertEq(storedUser, user);
        assertEq(storedTokenId, tokenId);
    }

    function testLpClaimCanBeAuthorizedWithoutTransferRights() public {
        uint256 managedId = _openLpPositionForUser();
        uint256 tokenId = 1;

        vm.prank(user);
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
                user,
                operator,
                address(lpWrapper),
                lpWrapper.transferManagedPosition.selector
            )
        );
        lpWrapper.transferManagedPosition(managedId, stranger);
    }

    function testBatchGrantLetsOperatorHandleMultipleLpFunctions() public {
        uint256 managedId = _openLpPositionForUser();

        IPermissionRegistry.PermissionKey[] memory keys = new IPermissionRegistry.PermissionKey[](2);
        keys[0] = IPermissionRegistry.PermissionKey(user, operator, address(lpWrapper), lpWrapper.addLiquidity.selector);
        keys[1] = IPermissionRegistry.PermissionKey(user, operator, address(lpWrapper), lpWrapper.claim.selector);

        vm.prank(user);
        registry.grantBatch(keys);

        vm.prank(operator);
        lpWrapper.addLiquidity(managedId, 250);

        (,,, uint128 liquidity,,) = lpManager.positions(1);
        assertEq(uint256(liquidity), 1_250);

        lpManager.seedFees(1, 9 ether, 4 ether);

        vm.prank(operator);
        (uint256 amount0, uint256 amount1) = lpWrapper.claim(managedId, recipient);

        assertEq(amount0, 9 ether);
        assertEq(amount1, 4 ether);
    }

    function testRevokeTurnsPermissionOff() public {
        uint256 managedId = _openLpPositionForUser();

        vm.startPrank(user);
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);
        registry.revoke(operator, address(lpWrapper), lpWrapper.claim.selector);
        vm.stopPrank();

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPermissionRegistry.PermissionDenied.selector,
                user,
                operator,
                address(lpWrapper),
                lpWrapper.claim.selector
            )
        );
        lpWrapper.claim(managedId, recipient);
    }

    function testPermissionIsScopedToTarget() public {
        vm.prank(user);
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);

        assertTrue(registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.claim.selector));
        assertFalse(registry.isAuthorizedCall(user, operator, address(lpManager), lpWrapper.claim.selector));
    }

    function testStakingRewardsCanBeClaimedWithoutUnstakeRights() public {
        uint256 managedId = _openStakeForUser();
        uint256 positionId = 1;

        vm.prank(user);
        registry.grant(operator, address(stakingWrapper), stakingWrapper.claimRewards.selector);

        stakingManager.seedRewards(positionId, 42 ether);

        vm.prank(operator);
        uint256 claimed = stakingWrapper.claimRewards(managedId, recipient);
        assertEq(claimed, 42 ether);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPermissionRegistry.PermissionDenied.selector,
                user,
                operator,
                address(stakingWrapper),
                stakingWrapper.unstake.selector
            )
        );
        stakingWrapper.unstake(managedId, 100);
    }

    function testTreasuryCanAuthorizeRebalanceWithoutControlTransfer() public {
        vm.prank(user);
        registry.grant(operator, address(treasury), treasury.rebalance.selector);

        vm.prank(operator);
        treasury.rebalance(user);
        assertEq(treasury.rebalances(user), 1);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPermissionRegistry.PermissionDenied.selector,
                user,
                operator,
                address(treasury),
                treasury.transferTreasuryControl.selector
            )
        );
        treasury.transferTreasuryControl(user, stranger);
    }

    // -------------------------------------------------------------------------
    // Expiry tests
    // -------------------------------------------------------------------------

    function testGrantWithExpiryWorksBeforeExpiry() public {
        uint256 managedId = _openLpPositionForUser();
        uint48 expiry = uint48(block.timestamp + 1 days);

        vm.prank(user);
        registry.grantWithExpiry(operator, address(lpWrapper), lpWrapper.claim.selector, expiry);

        assertTrue(registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.claim.selector));
        assertEq(registry.permissionExpiry(user, operator, address(lpWrapper), lpWrapper.claim.selector), expiry);

        lpManager.seedFees(1, 1 ether, 2 ether);
        vm.prank(operator);
        (uint256 a0, uint256 a1) = lpWrapper.claim(managedId, recipient);
        assertEq(a0, 1 ether);
        assertEq(a1, 2 ether);
    }

    function testGrantWithExpiryRevertsAfterExpiry() public {
        uint256 managedId = _openLpPositionForUser();
        uint48 expiry = uint48(block.timestamp + 1 days);

        vm.prank(user);
        registry.grantWithExpiry(operator, address(lpWrapper), lpWrapper.claim.selector, expiry);

        vm.warp(block.timestamp + 1 days + 1);

        assertFalse(registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.claim.selector));

        lpManager.seedFees(1, 1 ether, 2 ether);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPermissionRegistry.PermissionExpired.selector,
                user,
                operator,
                address(lpWrapper),
                lpWrapper.claim.selector
            )
        );
        lpWrapper.claim(managedId, recipient);
    }

    function testGrantPermanentIsUnaffectedByTime() public {
        uint256 managedId = _openLpPositionForUser();

        vm.prank(user);
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);

        vm.warp(block.timestamp + 365 days * 100);

        assertTrue(registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.claim.selector));

        lpManager.seedFees(1, 7 ether, 3 ether);
        vm.prank(operator);
        (uint256 a0, uint256 a1) = lpWrapper.claim(managedId, recipient);
        assertEq(a0, 7 ether);
        assertEq(a1, 3 ether);
    }

    // -------------------------------------------------------------------------
    // PermissionPermit tests
    // -------------------------------------------------------------------------

    function testPermitPermissionGrantsOnBehalfOfUser() public {
        uint256 userKey = 0xA11CE;
        address userAddr = vm.addr(userKey);

        uint256 managedId = _openLpPositionAs(userAddr);

        uint256 deadline = block.timestamp + 1 hours;
        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            user: userAddr,
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
                permit.user,
                permit.operator,
                permit.target,
                permit.selector,
                permit.expiry,
                permit.nonce,
                permit.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", registry.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        registry.permitPermission(permit, sig);

        assertTrue(registry.isAuthorizedCall(userAddr, operator, address(lpWrapper), lpWrapper.claim.selector));
        assertEq(registry.permissionNonce(userAddr), 1);

        lpManager.seedFees(1, 5 ether, 0);
        vm.prank(operator);
        (uint256 a0,) = lpWrapper.claim(managedId, recipient);
        assertEq(a0, 5 ether);
    }

    function testPermitFullAuthorizationGrantsEntireTargetOnBehalfOfUser() public {
        uint256 userKey = 0xA11CE;
        address userAddr = vm.addr(userKey);

        uint256 deadline = block.timestamp + 1 hours;
        IPermissionRegistry.FullAuthorizationPermit memory permit = IPermissionRegistry.FullAuthorizationPermit({
            user: userAddr,
            operator: operator,
            target: address(lpWrapper),
            expiry: type(uint48).max,
            nonce: 0,
            deadline: deadline
        });

        bytes32 structHash = keccak256(
            abi.encode(
                registry.FULL_AUTHORIZATION_PERMIT_TYPEHASH(),
                permit.user,
                permit.operator,
                permit.target,
                permit.expiry,
                permit.nonce,
                permit.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", registry.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, digest);

        registry.permitFullAuthorization(permit, abi.encodePacked(r, s, v));

        assertTrue(registry.isAuthorizedCall(userAddr, operator, address(lpWrapper), lpWrapper.claim.selector));
        assertTrue(
            registry.isAuthorizedCall(
                userAddr, operator, address(lpWrapper), lpWrapper.transferManagedPosition.selector
            )
        );
        assertEq(registry.permissionNonce(userAddr), 1);
        assertEq(registry.rawPermissionData(userAddr, operator, address(lpWrapper)).length, 4);
    }

    function testPermitFullAuthorizationCanRevokeEntireTarget() public {
        uint256 userKey = 0xA11CE;
        address userAddr = vm.addr(userKey);

        vm.prank(userAddr);
        registry.grantFull(operator, address(lpWrapper));
        assertTrue(registry.isAuthorizedCall(userAddr, operator, address(lpWrapper), lpWrapper.claim.selector));

        IPermissionRegistry.FullAuthorizationPermit memory permit = IPermissionRegistry.FullAuthorizationPermit({
            user: userAddr,
            operator: operator,
            target: address(lpWrapper),
            expiry: 0,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        bytes32 structHash = keccak256(
            abi.encode(
                registry.FULL_AUTHORIZATION_PERMIT_TYPEHASH(),
                permit.user,
                permit.operator,
                permit.target,
                permit.expiry,
                permit.nonce,
                permit.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", registry.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, digest);

        registry.permitFullAuthorization(permit, abi.encodePacked(r, s, v));

        assertFalse(registry.isAuthorizedCall(userAddr, operator, address(lpWrapper), lpWrapper.claim.selector));
        assertEq(registry.rawPermissionData(userAddr, operator, address(lpWrapper)).length, 0);
    }

    function testPermitPermissionRevokeOnBehalfOfUser() public {
        uint256 userKey = 0xA11CE;
        address userAddr = vm.addr(userKey);

        vm.prank(userAddr);
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);
        assertTrue(registry.isAuthorizedCall(userAddr, operator, address(lpWrapper), lpWrapper.claim.selector));

        uint256 deadline = block.timestamp + 1 hours;
        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            user: userAddr,
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
                permit.user,
                permit.operator,
                permit.target,
                permit.selector,
                permit.expiry,
                permit.nonce,
                permit.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", registry.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, digest);

        registry.permitPermission(permit, abi.encodePacked(r, s, v));

        assertFalse(registry.isAuthorizedCall(userAddr, operator, address(lpWrapper), lpWrapper.claim.selector));
    }

    function testPermitPermissionRejectsWrongSigner() public {
        uint256 userKey = 0xA11CE;
        uint256 wrongKey = 0xBAD;
        address userAddr = vm.addr(userKey);

        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            user: userAddr,
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
                permit.user,
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
        uint256 userKey = 0xA11CE;
        address userAddr = vm.addr(userKey);

        uint256 deadline = block.timestamp - 1;
        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            user: userAddr,
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
                permit.user,
                permit.operator,
                permit.target,
                permit.selector,
                permit.expiry,
                permit.nonce,
                permit.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", registry.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, digest);

        vm.expectRevert(IPermissionRegistry.DeadlineExpired.selector);
        registry.permitPermission(permit, abi.encodePacked(r, s, v));
    }

    function testPermitPermissionRejectsReplay() public {
        uint256 userKey = 0xA11CE;
        address userAddr = vm.addr(userKey);

        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            user: userAddr,
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
                permit.user,
                permit.operator,
                permit.target,
                permit.selector,
                permit.expiry,
                permit.nonce,
                permit.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", registry.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, digest);
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

        vm.prank(user);
        registry.grantWithExpiry(operator, address(lpWrapper), lpWrapper.claim.selector, expiry);

        vm.warp(expiry); // exactly at expiry

        assertTrue(registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.claim.selector));
    }

    function testExpiryIsExpiredOneSecondAfterBoundary() public {
        uint48 expiry = uint48(block.timestamp + 1 days);

        vm.prank(user);
        registry.grantWithExpiry(operator, address(lpWrapper), lpWrapper.claim.selector, expiry);

        vm.warp(expiry + 1);

        assertFalse(registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.claim.selector));
    }

    function testGrantWithExpiryAtCurrentTimestampReverts() public {
        uint48 now_ = uint48(block.timestamp);
        vm.prank(user);
        vm.expectRevert(IPermissionRegistry.InvalidExpiry.selector);
        registry.grantWithExpiry(operator, address(lpWrapper), lpWrapper.claim.selector, now_);
    }

    // -------------------------------------------------------------------------
    // Expiry overwrite semantics
    // -------------------------------------------------------------------------

    function testGrantOverwritesExpiryWithPermanent() public {
        uint256 managedId = _openLpPositionForUser();
        uint48 expiry = uint48(block.timestamp + 1 days);

        vm.startPrank(user);
        registry.grantWithExpiry(operator, address(lpWrapper), lpWrapper.claim.selector, expiry);
        // Overwrite with a permanent grant before it expires.
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);
        vm.stopPrank();

        vm.warp(expiry + 1); // past the original expiry

        assertTrue(registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.claim.selector));

        lpManager.seedFees(1, 1 ether, 0);
        vm.prank(operator);
        lpWrapper.claim(managedId, recipient);
    }

    function testGrantWithExpiryOverwritesPermanentGrant() public {
        uint256 managedId = _openLpPositionForUser();
        uint48 expiry = uint48(block.timestamp + 1 days);

        vm.startPrank(user);
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);
        // Downgrade to a time-bounded permission.
        registry.grantWithExpiry(operator, address(lpWrapper), lpWrapper.claim.selector, expiry);
        vm.stopPrank();

        vm.warp(expiry + 1);

        assertFalse(registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.claim.selector));

        lpManager.seedFees(1, 1 ether, 0);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPermissionRegistry.PermissionExpired.selector,
                user,
                operator,
                address(lpWrapper),
                lpWrapper.claim.selector
            )
        );
        lpWrapper.claim(managedId, recipient);
    }

    // -------------------------------------------------------------------------
    // Permission space isolation
    // -------------------------------------------------------------------------

    function testStrangerRevokeCannotTouchUserPermission() public {
        // The user is the primary key in the permission mapping.
        // A stranger calling revoke() can only zero out their OWN (stranger -> operator) slot.
        uint256 managedId = _openLpPositionForUser();

        vm.prank(user);
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);

        // Stranger tries to revoke the user's grant — this only writes to
        // permissions[stranger][operator][...] which was never set.
        vm.prank(stranger);
        registry.revoke(operator, address(lpWrapper), lpWrapper.claim.selector);

        // User's permission is untouched.
        assertTrue(registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.claim.selector));

        lpManager.seedFees(1, 1 ether, 0);
        vm.prank(operator);
        lpWrapper.claim(managedId, recipient);
    }

    function testOperatorCannotRevokeTheirOwnIncomingGrant() public {
        // Operator calls revoke(user, target, selector) which writes to
        // permissions[operator][user][target][selector] — the slot where
        // operator would be the *user*, not their incoming permission.
        uint256 managedId = _openLpPositionForUser();

        vm.prank(user);
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);

        // Operator tries to self-revoke.
        vm.prank(operator);
        registry.revoke(user, address(lpWrapper), lpWrapper.claim.selector);

        // The grant from user -> operator is still intact.
        assertTrue(registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.claim.selector));

        lpManager.seedFees(1, 1 ether, 0);
        vm.prank(operator);
        lpWrapper.claim(managedId, recipient);
    }

    function testTwoUsersGrantingToSameOperatorAreIndependent() public {
        address userB = makeAddr("userB");

        vm.prank(user);
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);

        vm.prank(userB);
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);

        // User A revokes — user B's grant must survive.
        vm.prank(user);
        registry.revoke(operator, address(lpWrapper), lpWrapper.claim.selector);

        assertFalse(registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.claim.selector));
        assertTrue(registry.isAuthorizedCall(userB, operator, address(lpWrapper), lpWrapper.claim.selector));
    }

    // -------------------------------------------------------------------------
    // Batch atomicity
    // -------------------------------------------------------------------------

    function testBatchGrantIsAtomicOnUserMismatch() public {
        address userB = makeAddr("userB");

        IPermissionRegistry.PermissionKey[] memory keys = new IPermissionRegistry.PermissionKey[](3);
        keys[0] = IPermissionRegistry.PermissionKey(user, operator, address(lpWrapper), lpWrapper.claim.selector);
        keys[1] =
            IPermissionRegistry.PermissionKey(userB, operator, address(lpWrapper), lpWrapper.addLiquidity.selector); // wrong user
        keys[2] = IPermissionRegistry.PermissionKey(user, operator, address(lpWrapper), lpWrapper.addLiquidity.selector);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPermissionRegistry.PermissionDenied.selector,
                userB,
                user,
                address(lpWrapper),
                lpWrapper.addLiquidity.selector
            )
        );
        registry.grantBatch(keys);

        // No partial state — keys[0] must not have been set.
        assertFalse(registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.claim.selector));
        assertFalse(registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.addLiquidity.selector));
    }

    // -------------------------------------------------------------------------
    // Input validation
    // -------------------------------------------------------------------------

    function testGrantRevertsOnZeroOperator() public {
        vm.prank(user);
        vm.expectRevert(IPermissionRegistry.InvalidAddress.selector);
        registry.grant(address(0), address(lpWrapper), lpWrapper.claim.selector);
    }

    function testGrantRevertsOnZeroTarget() public {
        vm.prank(user);
        vm.expectRevert(IPermissionRegistry.InvalidAddress.selector);
        registry.grant(operator, address(0), lpWrapper.claim.selector);
    }

    function testGrantRevertsOnZeroSelector() public {
        vm.prank(user);
        vm.expectRevert(IPermissionRegistry.InvalidSelector.selector);
        registry.grant(operator, address(lpWrapper), bytes4(0));
    }

    function testRevokeNonexistentPermissionDoesNotRevert() public {
        // Revoke on a slot that was never set should silently succeed.
        vm.prank(user);
        registry.revoke(operator, address(lpWrapper), lpWrapper.claim.selector);

        assertFalse(registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.claim.selector));
    }

    function testSelfGrantUserAsOperator() public {
        // A user granting themselves is unusual but not disallowed.
        uint256 managedId = _openLpPositionForUser();

        vm.prank(user);
        registry.grant(user, address(lpWrapper), lpWrapper.claim.selector);

        assertTrue(registry.isAuthorizedCall(user, user, address(lpWrapper), lpWrapper.claim.selector));

        lpManager.seedFees(1, 2 ether, 1 ether);
        // User calling directly still works (short-circuits registry check).
        vm.prank(user);
        lpWrapper.claim(managedId, recipient);
    }

    // -------------------------------------------------------------------------
    // Permit edge cases
    // -------------------------------------------------------------------------

    function testPermitWithSkippedNonceReverts() public {
        uint256 userKey = 0xA11CE;
        address userAddr = vm.addr(userKey);

        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            user: userAddr,
            operator: operator,
            target: address(lpWrapper),
            selector: lpWrapper.claim.selector,
            expiry: type(uint48).max,
            nonce: 5, // current nonce is 0
            deadline: block.timestamp + 1 hours
        });

        bytes memory sig = _signPermit(userKey, permit);
        vm.expectRevert(abi.encodeWithSelector(IPermissionRegistry.InvalidNonce.selector, uint256(0), uint256(5)));
        registry.permitPermission(permit, sig);
    }

    function testPermitDeadlineAtCurrentTimestampIsValid() public {
        // Deadline check is strict: reverts only when block.timestamp > deadline.
        // deadline == block.timestamp should pass.
        uint256 userKey = 0xA11CE;
        address userAddr = vm.addr(userKey);

        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            user: userAddr,
            operator: operator,
            target: address(lpWrapper),
            selector: lpWrapper.claim.selector,
            expiry: type(uint48).max,
            nonce: 0,
            deadline: block.timestamp // exactly now
        });

        registry.permitPermission(permit, _signPermit(userKey, permit));

        assertTrue(registry.isAuthorizedCall(userAddr, operator, address(lpWrapper), lpWrapper.claim.selector));
    }

    function testPermitGrantedPermissionCanBeRevokedDirectly() public {
        uint256 userKey = 0xA11CE;
        address userAddr = vm.addr(userKey);

        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            user: userAddr,
            operator: operator,
            target: address(lpWrapper),
            selector: lpWrapper.claim.selector,
            expiry: type(uint48).max,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        registry.permitPermission(permit, _signPermit(userKey, permit));
        assertTrue(registry.isAuthorizedCall(userAddr, operator, address(lpWrapper), lpWrapper.claim.selector));

        // User revokes the permit-granted permission directly.
        vm.prank(userAddr);
        registry.revoke(operator, address(lpWrapper), lpWrapper.claim.selector);

        assertFalse(registry.isAuthorizedCall(userAddr, operator, address(lpWrapper), lpWrapper.claim.selector));
    }

    function testPermitCanGrantTimeBoundedPermission() public {
        uint256 userKey = 0xA11CE;
        address userAddr = vm.addr(userKey);
        uint48 expiry = uint48(block.timestamp + 7 days);

        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            user: userAddr,
            operator: operator,
            target: address(lpWrapper),
            selector: lpWrapper.claim.selector,
            expiry: expiry,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        registry.permitPermission(permit, _signPermit(userKey, permit));

        assertEq(registry.permissionExpiry(userAddr, operator, address(lpWrapper), lpWrapper.claim.selector), expiry);

        vm.warp(expiry + 1);
        assertFalse(registry.isAuthorizedCall(userAddr, operator, address(lpWrapper), lpWrapper.claim.selector));
    }

    function testPermitWithAlreadyExpiredExpiryReverts() public {
        uint256 userKey = 0xA11CE;
        address userAddr = vm.addr(userKey);

        vm.warp(1_000_000);

        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            user: userAddr,
            operator: operator,
            target: address(lpWrapper),
            selector: lpWrapper.claim.selector,
            expiry: uint48(block.timestamp - 1), // already expired
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        bytes memory sig = _signPermit(userKey, permit);
        vm.expectRevert(IPermissionRegistry.InvalidExpiry.selector);
        registry.permitPermission(permit, sig);
    }

    // -------------------------------------------------------------------------
    // Signature security
    // -------------------------------------------------------------------------

    function testHighSSignatureIsRejected() public {
        // A malleable (high-s) twin of a valid signature must be rejected.
        uint256 userKey = 0xA11CE;
        address userAddr = vm.addr(userKey);

        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            user: userAddr,
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
                permit.user,
                permit.operator,
                permit.target,
                permit.selector,
                permit.expiry,
                permit.nonce,
                permit.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", registry.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, digest);

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
        uint256 userKey = 0xA11CE;
        address userAddr = vm.addr(userKey);

        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            user: userAddr,
            operator: operator,
            target: address(lpWrapper),
            selector: lpWrapper.claim.selector,
            expiry: type(uint48).max,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        bytes memory sig = _signPermit(userKey, permit);

        // Swap in a different operator after signing.
        permit.operator = stranger;

        vm.expectRevert(IPermissionRegistry.InvalidSignature.selector);
        registry.permitPermission(permit, sig);
    }

    function testPermitExpiryMutationInvalidatesSignature() public {
        uint256 userKey = 0xA11CE;
        address userAddr = vm.addr(userKey);

        IPermissionRegistry.PermissionPermit memory permit = IPermissionRegistry.PermissionPermit({
            user: userAddr,
            operator: operator,
            target: address(lpWrapper),
            selector: lpWrapper.claim.selector,
            expiry: uint48(block.timestamp + 7 days),
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        bytes memory sig = _signPermit(userKey, permit);

        // Inflate the expiry after signing.
        permit.expiry = type(uint48).max;

        vm.expectRevert(IPermissionRegistry.InvalidSignature.selector);
        registry.permitPermission(permit, sig);
    }

    // -------------------------------------------------------------------------
    // Packed auth bytes / full approval tests
    // -------------------------------------------------------------------------

    function testFullApprovalAuthorizesAllSelectorsOnTarget() public {
        uint256 managedId = _openLpPositionForUser();

        vm.prank(user);
        registry.grantFull(operator, address(lpWrapper));

        assertTrue(registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.claim.selector));
        assertTrue(
            registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.transferManagedPosition.selector)
        );
        assertEq(registry.rawPermissionData(user, operator, address(lpWrapper)).length, 4);

        lpManager.seedFees(1, 3 ether, 5 ether);
        vm.prank(operator);
        lpWrapper.claim(managedId, recipient);

        vm.prank(operator);
        lpWrapper.transferManagedPosition(managedId, stranger);
    }

    function testRevokeAllClearsFullApproval() public {
        uint256 managedId = _openLpPositionForUser();

        vm.startPrank(user);
        registry.grantFull(operator, address(lpWrapper));
        registry.revokeAll(operator, address(lpWrapper));
        vm.stopPrank();

        assertFalse(registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.claim.selector));
        assertEq(registry.rawPermissionData(user, operator, address(lpWrapper)).length, 0);

        lpManager.seedFees(1, 1 ether, 2 ether);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPermissionRegistry.PermissionDenied.selector,
                user,
                operator,
                address(lpWrapper),
                lpWrapper.claim.selector
            )
        );
        lpWrapper.claim(managedId, recipient);
    }

    function testGrantFullWithExpiryAcceptsPermanentSentinel() public {
        vm.prank(user);
        registry.grantFullWithExpiry(operator, address(lpWrapper), type(uint48).max);

        assertTrue(registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.claim.selector));
        assertEq(
            registry.permissionExpiry(user, operator, address(lpWrapper), lpWrapper.claim.selector), type(uint48).max
        );
    }

    function testGrantWithExpiryAcceptsPermanentSentinel() public {
        vm.prank(user);
        registry.grantWithExpiry(operator, address(lpWrapper), lpWrapper.claim.selector, type(uint48).max);

        assertTrue(registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.claim.selector));
        assertEq(
            registry.permissionExpiry(user, operator, address(lpWrapper), lpWrapper.claim.selector), type(uint48).max
        );
    }

    function testSelectorGrantDoesNotMutateExistingFullApproval() public {
        uint48 fullExpiry = uint48(block.timestamp + 10 days);
        uint48 shorterSelectorExpiry = uint48(block.timestamp + 1 days);

        vm.prank(user);
        registry.grantFullWithExpiry(operator, address(lpWrapper), fullExpiry);

        vm.prank(user);
        registry.grantWithExpiry(operator, address(lpWrapper), lpWrapper.claim.selector, shorterSelectorExpiry);

        assertEq(registry.permissionExpiry(user, operator, address(lpWrapper), lpWrapper.claim.selector), fullExpiry);
        assertEq(registry.rawPermissionData(user, operator, address(lpWrapper)).length, 4);
    }

    function testSelectorGrantReplacesExpiredFullApproval() public {
        uint48 fullExpiry = uint48(block.timestamp + 1 days);

        vm.prank(user);
        registry.grantFullWithExpiry(operator, address(lpWrapper), fullExpiry);

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(user);
        registry.grant(operator, address(lpWrapper), lpWrapper.claim.selector);

        assertTrue(registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.claim.selector));
        assertFalse(
            registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.transferManagedPosition.selector)
        );
        assertEq(registry.rawPermissionData(user, operator, address(lpWrapper)).length, 8);
    }

    function testSelectorBundleRequiresSortedUniqueSelectors() public {
        bytes4[] memory unsorted = new bytes4[](2);
        unsorted[0] = bytes4(uint32(2));
        unsorted[1] = bytes4(uint32(1));

        vm.prank(user);
        vm.expectRevert(IPermissionRegistry.InvalidSelector.selector);
        registry.grantSelectorBundle(operator, address(lpWrapper), unsorted, type(uint48).max);

        bytes4[] memory sorted = new bytes4[](2);
        sorted[0] = lpWrapper.claim.selector < lpWrapper.transferManagedPosition.selector
            ? lpWrapper.claim.selector
            : lpWrapper.transferManagedPosition.selector;
        sorted[1] = lpWrapper.claim.selector < lpWrapper.transferManagedPosition.selector
            ? lpWrapper.transferManagedPosition.selector
            : lpWrapper.claim.selector;

        vm.prank(user);
        registry.grantSelectorBundle(operator, address(lpWrapper), sorted, type(uint48).max);

        assertTrue(registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.claim.selector));
        assertTrue(
            registry.isAuthorizedCall(user, operator, address(lpWrapper), lpWrapper.transferManagedPosition.selector)
        );
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
                permit.user,
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

    function _openLpPositionForUser() internal returns (uint256 managedId) {
        vm.prank(user);
        (managedId,) = lpWrapper.openManagedPosition(user, -60, 60, 1_000);
    }

    function _openLpPositionAs(address userAddr) internal returns (uint256 managedId) {
        vm.prank(userAddr);
        (managedId,) = lpWrapper.openManagedPosition(userAddr, -60, 60, 1_000);
    }

    function _openStakeForUser() internal returns (uint256 managedId) {
        vm.prank(user);
        (managedId,) = stakingWrapper.openManagedStake(user, 1_000);
    }
}

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

    function _openLpPositionForOwner() internal returns (uint256 managedId) {
        vm.prank(owner);
        (managedId,) = lpWrapper.openManagedPosition(owner, -60, 60, 1_000);
    }

    function _openStakeForOwner() internal returns (uint256 managedId) {
        vm.prank(owner);
        (managedId,) = stakingWrapper.openManagedStake(owner, 1_000);
    }
}

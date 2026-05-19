// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "./Test.sol";
import {PermissionRegistry} from "src/PermissionRegistry.sol";
import {IPermissionRegistry} from "src/interfaces/IPermissionRegistry.sol";

contract AuthGasBench is Test {
    event GasUsed(string name, uint256 n, uint256 gasUsed);

    PermissionRegistry internal registry;
    address internal owner = address(0xA11CE);
    address internal operator = address(0xB0B);
    address internal target = address(0xCAFE);

    function setUp() public {
        registry = new PermissionRegistry();
    }

    function testGasGrantFullFresh() public {
        vm.prank(owner);
        uint256 start = gasleft();
        registry.grantFull(operator, target);
        emit GasUsed("grantFullFresh", 0, start - gasleft());
    }

    function testGasCheckFull() public {
        vm.prank(owner);
        registry.grantFull(operator, target);
        uint256 start = gasleft();
        bool ok = registry.isAuthorizedCall(owner, operator, target, bytes4(uint32(1)));
        emit GasUsed("checkFull", 0, start - gasleft());
        assertTrue(ok);
    }

    function testGasGrantBundle1Fresh() public { _benchGrantBundle(1); }
    function testGasGrantBundle2Fresh() public { _benchGrantBundle(2); }
    function testGasGrantBundle3Fresh() public { _benchGrantBundle(3); }
    function testGasGrantBundle6Fresh() public { _benchGrantBundle(6); }
    function testGasGrantBundle7Fresh() public { _benchGrantBundle(7); }
    function testGasGrantBundle10Fresh() public { _benchGrantBundle(10); }
    function testGasGrantBundle20Fresh() public { _benchGrantBundle(20); }
    function testGasGrantBundle40Fresh() public { _benchGrantBundle(40); }

    function testGasCheckBundle1Worst() public { _benchCheckBundle(1); }
    function testGasCheckBundle2Worst() public { _benchCheckBundle(2); }
    function testGasCheckBundle3Worst() public { _benchCheckBundle(3); }
    function testGasCheckBundle6Worst() public { _benchCheckBundle(6); }
    function testGasCheckBundle7Worst() public { _benchCheckBundle(7); }
    function testGasCheckBundle10Worst() public { _benchCheckBundle(10); }
    function testGasCheckBundle20Worst() public { _benchCheckBundle(20); }
    function testGasCheckBundle40Worst() public { _benchCheckBundle(40); }

    function testGasGrantBatch1Fresh() public { _benchGrantBatch(1); }
    function testGasGrantBatch2Fresh() public { _benchGrantBatch(2); }
    function testGasGrantBatch3Fresh() public { _benchGrantBatch(3); }
    function testGasGrantBatch6Fresh() public { _benchGrantBatch(6); }
    function testGasGrantBatch7Fresh() public { _benchGrantBatch(7); }
    function testGasGrantBatch10Fresh() public { _benchGrantBatch(10); }
    function testGasGrantBatch20Fresh() public { _benchGrantBatch(20); }
    function testGasGrantBatch40Fresh() public { _benchGrantBatch(40); }

    function testGasCheckBatch1Worst() public { _benchCheckBatch(1); }
    function testGasCheckBatch2Worst() public { _benchCheckBatch(2); }
    function testGasCheckBatch3Worst() public { _benchCheckBatch(3); }
    function testGasCheckBatch6Worst() public { _benchCheckBatch(6); }
    function testGasCheckBatch7Worst() public { _benchCheckBatch(7); }
    function testGasCheckBatch10Worst() public { _benchCheckBatch(10); }
    function testGasCheckBatch20Worst() public { _benchCheckBatch(20); }
    function testGasCheckBatch40Worst() public { _benchCheckBatch(40); }

    function _benchGrantBundle(uint256 n) internal {
        bytes4[] memory selectors = _selectors(n);
        vm.prank(owner);
        uint256 start = gasleft();
        registry.grantSelectorBundle(operator, target, selectors, type(uint48).max);
        emit GasUsed("grantBundleFresh", n, start - gasleft());
    }

    function _benchCheckBundle(uint256 n) internal {
        bytes4[] memory selectors = _selectors(n);
        vm.prank(owner);
        registry.grantSelectorBundle(operator, target, selectors, type(uint48).max);
        uint256 start = gasleft();
        bool ok = registry.isAuthorizedCall(owner, operator, target, selectors[n - 1]);
        emit GasUsed("checkBundleWorst", n, start - gasleft());
        assertTrue(ok);
    }

    function _benchGrantBatch(uint256 n) internal {
        IPermissionRegistry.PermissionKey[] memory keys = _keys(n);
        vm.prank(owner);
        uint256 start = gasleft();
        registry.grantBatch(keys);
        emit GasUsed("grantBatchFresh", n, start - gasleft());
    }

    function _benchCheckBatch(uint256 n) internal {
        IPermissionRegistry.PermissionKey[] memory keys = _keys(n);
        vm.prank(owner);
        registry.grantBatch(keys);
        bytes4 selector = keys[n - 1].selector;
        uint256 start = gasleft();
        bool ok = registry.isAuthorizedCall(owner, operator, target, selector);
        emit GasUsed("checkBatchWorst", n, start - gasleft());
        assertTrue(ok);
    }

    function _keys(uint256 n) internal view returns (IPermissionRegistry.PermissionKey[] memory keys) {
        keys = new IPermissionRegistry.PermissionKey[](n);
        bytes4[] memory selectors = _selectors(n);
        for (uint256 i; i < n; ++i) {
            keys[i] = IPermissionRegistry.PermissionKey(owner, operator, target, selectors[i]);
        }
    }

    function _selectors(uint256 n) internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](n);
        for (uint256 i; i < n; ++i) {
            selectors[i] = bytes4(uint32(i + 1));
        }
    }
}

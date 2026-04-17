// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface Vm {
    function addr(uint256 privateKey) external returns (address keyAddr);
    function label(address account, string calldata newLabel) external;
    function sign(uint256 privateKey, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);
    function prank(address msgSender) external;
    function startPrank(address msgSender) external;
    function stopPrank() external;
    function expectRevert(bytes calldata revertData) external;
    function expectRevert(bytes4 revertData) external;
}

abstract contract Test {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function makeAddr(string memory name) internal returns (address addr) {
        addr = address(uint160(uint256(keccak256(bytes(name)))));
        vm.label(addr, name);
    }

    function assertTrue(bool condition) internal pure {
        require(condition, "assertTrue failed");
    }

    function assertFalse(bool condition) internal pure {
        require(!condition, "assertFalse failed");
    }

    function assertEq(uint256 a, uint256 b) internal pure {
        require(a == b, "assertEq(uint256) failed");
    }

    function assertEq(address a, address b) internal pure {
        require(a == b, "assertEq(address) failed");
    }
}

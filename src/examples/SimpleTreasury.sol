// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PermissionedTarget} from "../base/PermissionedTarget.sol";

/// @notice Tiny non-wrapper example showing function-scoped auth on a treasury-like contract.
contract SimpleTreasury is PermissionedTarget {
    mapping(address owner => uint256 feesClaimed) public claimedFees;
    mapping(address owner => uint256 rebalanceCount) public rebalances;
    mapping(address owner => address treasuryOwner) public delegates;

    event FeesClaimed(address indexed owner, address indexed recipient, uint256 amount);
    event Rebalanced(address indexed owner, uint256 newCount);
    event TreasuryControlTransferred(address indexed owner, address indexed newOwner);

    constructor(address registry_) PermissionedTarget(registry_) {}

    function claimFees(address owner, address recipient, uint256 amount) external onlyAuthorized(owner) {
        claimedFees[owner] += amount;
        emit FeesClaimed(owner, recipient, amount);
    }

    function rebalance(address owner) external onlyAuthorized(owner) {
        rebalances[owner] += 1;
        emit Rebalanced(owner, rebalances[owner]);
    }

    function transferTreasuryControl(address owner, address newOwner) external onlyAuthorized(owner) {
        delegates[owner] = newOwner;
        emit TreasuryControlTransferred(owner, newOwner);
    }
}

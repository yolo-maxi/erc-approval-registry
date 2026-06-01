// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PermissionedTarget} from "../base/PermissionedTarget.sol";

/// @notice Tiny non-wrapper example showing function-scoped auth on a treasury-like contract.
contract SimpleTreasury is PermissionedTarget {
    mapping(address user => uint256 feesClaimed) public claimedFees;
    mapping(address user => uint256 rebalanceCount) public rebalances;
    mapping(address user => address treasuryDelegate) public delegates;

    event FeesClaimed(address indexed user, address indexed recipient, uint256 amount);
    event Rebalanced(address indexed user, uint256 newCount);
    event TreasuryControlTransferred(address indexed user, address indexed newUser);

    constructor(address registry_) PermissionedTarget(registry_) {}

    function claimFees(address user, address recipient, uint256 amount) external onlyAuthorized(user) {
        claimedFees[user] += amount;
        emit FeesClaimed(user, recipient, amount);
    }

    function rebalance(address user) external onlyAuthorized(user) {
        rebalances[user] += 1;
        emit Rebalanced(user, rebalances[user]);
    }

    function transferTreasuryControl(address user, address newUser) external onlyAuthorized(user) {
        delegates[user] = newUser;
        emit TreasuryControlTransferred(user, newUser);
    }
}

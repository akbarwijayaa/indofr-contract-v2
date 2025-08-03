// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;


struct lockInfo {
    uint256 amount;
    uint256 lockPeriod;
    uint256 pendingReward;
    uint256 claimedReward;
    bool withdrawn;
    bool claimed;
}
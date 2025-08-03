// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

interface IReward {
    function calculateReward(uint256 amount, uint256 lockPeriod) external view returns (uint256);
}

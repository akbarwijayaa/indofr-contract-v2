// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IMarket} from "./interfaces/IMarket.sol";
import {lockInfo} from "./types/StructType.sol";

contract Reward is Ownable, ReentrancyGuard {
    IERC20 public rewardToken;
    IMarket public market;

    uint256 private totalDepositedRewards;
    uint256 public totalPromisedRewards;
    uint256 private claimedRewards;

    mapping(uint256 => uint256) public rewardRates;
    mapping(uint256 => uint256) public rewardDueAt;

    event DepositReward(address indexed user, uint256 amount);
    event ClaimReward(address indexed user, uint256 positionIndex, uint256 amount);

    error InsufficientBalance();
    error ZeroAmount();
    error InvalidMarketAddress();
    error Unauthorized();
    error ZeroTVL();
    error InvalidClaimedStatus();

    constructor(address _rewardToken, address _market, address owner) Ownable(owner) {
        if (_rewardToken == address(0)) revert ZeroAmount();
        if (_market == address(0)) revert InvalidMarketAddress();

        rewardToken = IERC20(_rewardToken);
        market = IMarket(_market);
    }

    function depositReward(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (rewardToken.balanceOf(msg.sender) < amount) revert InsufficientBalance();
        if (market.tvl() == 0) revert ZeroTVL();
        if (amount + (totalDepositedRewards - claimedRewards) > totalPromisedRewards) revert InvalidClaimedStatus();

        totalDepositedRewards += amount;
        rewardToken.transferFrom(msg.sender, address(this), amount);

        emit DepositReward(msg.sender, amount);
    }

    function setRewardRate(uint256 lockPeriod, uint256 rateApy) external onlyOwner {
        rewardRates[lockPeriod] = rateApy;
    }

    function calculateUserReward(uint256 amount, uint256 lockPeriod) external view returns (uint256) {
        uint256 rateApy = rewardRates[lockPeriod];
        uint256 reward = (amount * rateApy * lockPeriod) / (365 days * 10000);

        return reward;
    }

    function _calculateReward(uint256 amount, uint256 lockPeriod) external onlyMarket returns (uint256, uint256) {
        uint256 rateApy = rewardRates[lockPeriod];
        uint256 reward = (amount * rateApy * lockPeriod) / (365 days * 10000);

        totalPromisedRewards += reward;
        uint256 lockEndTime = block.timestamp + lockPeriod;
        rewardDueAt[lockEndTime] += reward;

        return (reward, lockEndTime);
    }

    function claimReward(address user, uint256 positionIndex) external nonReentrant {
        if (msg.sender != user) revert Unauthorized();

        (,, uint256 lockEndTime, uint256 pendingReward,,, bool claimed) = market.userPositions(user, positionIndex);
        if (claimed) revert InvalidClaimedStatus();
        if (pendingReward == 0) revert ZeroAmount();
        if (rewardToken.balanceOf(address(this)) < pendingReward) revert InsufficientBalance();

        totalPromisedRewards -= pendingReward;
        rewardDueAt[lockEndTime] -= pendingReward;
        claimedRewards += pendingReward;

        market.updateClaimedStatus(user, positionIndex, pendingReward);
        rewardToken.transfer(user, pendingReward);

        emit ClaimReward(user, positionIndex, pendingReward);
    }

    function getTotalLackRewards() external view returns (uint256) {
        return totalDepositedRewards - claimedRewards;
    }

    modifier onlyMarket() {
        if (msg.sender != address(market)) revert Unauthorized();
        _;
    }
}

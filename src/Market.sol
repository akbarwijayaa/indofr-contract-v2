// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { lockInfo } from "./types/StructType.sol";
import { Reward } from "./Reward.sol";

contract Market is Ownable {
    string public marketName;
    address public tokenAccepted;
    uint256 public tvl;
    uint256 public maxSupply;

    Reward public reward;
    address public rewardAddress;

    mapping(address => lockInfo[]) public userPositions;
    mapping(address => mapping(uint256 => uint256)) public lockStartTime;


    event Deposit(address indexed to, uint256 amount);
    event Redeem(address indexed to, uint256 amount);
    event DepositAsOwner(uint256 amount);
    event WithdrawToOwner(address indexed from, address indexed to, uint256 amount);
    event MarketRolledOver(address indexed user, uint256 amount, uint256 newLockPeriod);

    error TokenNotAccepted();
    error MaxSupplyExceeded();
    error InvalidMaxSupply();
    error InsufficientBalance();
    error StillLockedPeriod();
    error ZeroAmount();
    error AlreadyWithdrawn();
    error InvalidMarketAddress();
    error InvalidAmount();
    error MarketNotMatured();
    error InvalidClaimedStatus();
    error Unauthorized();

    constructor (
        string memory _marketName,
        address _tokenAccepted,
        uint256 _maxSupply
    ) Ownable(msg.sender) {
        if (msg.sender == address(0)) revert ZeroAmount();
        if (bytes(_marketName).length == 0) revert ZeroAmount();
        if (_tokenAccepted == address(0)) revert ZeroAmount();
        if (_maxSupply == 0) revert InvalidMaxSupply();

        marketName = _marketName;
        tokenAccepted = _tokenAccepted;
        maxSupply = _maxSupply;

        reward = new Reward(_tokenAccepted, address(this), msg.sender);
        rewardAddress = address(reward);
    }

    function deposit(address to, address tokenIn, uint256 amount, uint256 lockPeriod) external {
        if (IERC20(tokenIn).balanceOf(msg.sender) < amount) revert InsufficientBalance();
        if (tokenIn != tokenAccepted) revert TokenNotAccepted();
        if (tvl + amount > maxSupply) revert MaxSupplyExceeded();

        IERC20(tokenAccepted).transferFrom(msg.sender, address(this), amount);

        uint256 pendingReward = reward._calculateReward(amount, lockPeriod);

        uint256 positionIndex = userPositions[msg.sender].length;
        lockStartTime[msg.sender][positionIndex] = block.timestamp;
        
        userPositions[msg.sender].push(lockInfo({
            amount: amount,
            lockPeriod: lockPeriod,
            pendingReward: pendingReward,
            claimedReward: 0,
            withdrawn: false,
            claimed: false
        }));

        tvl += amount;

        emit Deposit(to, amount);
    }


    function redeem(uint index) external {
        lockInfo storage lock = userPositions[msg.sender][index];

        if (lock.withdrawn) revert AlreadyWithdrawn();
        if (block.timestamp < lockStartTime[msg.sender][index] + lock.lockPeriod) revert StillLockedPeriod();
        if (lock.amount == 0) revert ZeroAmount();

        lock.withdrawn = true;
        IERC20(tokenAccepted).transfer(msg.sender, lock.amount);
        tvl -= lock.amount;

        emit Redeem(msg.sender, index);
    }


    function depositAsOwner(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();

        IERC20(tokenAccepted).transferFrom(msg.sender, address(this), amount);
        emit DepositAsOwner(amount);
    }
    

    function redeemToOwner(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (amount > IERC20(tokenAccepted).balanceOf(address(this))) revert InsufficientBalance();

        IERC20(tokenAccepted).transfer(msg.sender, amount);
        emit WithdrawToOwner(address(this), msg.sender, amount);
    }

    function balanceOf(address account) external view returns (uint256) {
        uint256 total;
        lockInfo[] storage locks = userPositions[account];
        for (uint256 i = 0; i < locks.length; i++) {
            if (!locks[i].withdrawn) {
                total += locks[i].amount;
            }
        }
        return total;
    }


    function userLockCount(address user) external view returns (uint256) {
        return userPositions[user].length;
    }


    function getRedeemableIndexes(address user) external view returns (uint256[] memory) {
        lockInfo[] storage locks = userPositions[user];
        uint256 count;
        for (uint256 i = 0; i < locks.length; i++) {
            if (!locks[i].withdrawn && block.timestamp >= lockStartTime[user][i] + locks[i].lockPeriod && locks[i].amount > 0) {
                count++;
            }
        }
        uint256[] memory indexes = new uint256[](count);
        uint256 j;
        for (uint256 i = 0; i < locks.length; i++) {
            if (!locks[i].withdrawn && block.timestamp >= lockStartTime[user][i] + locks[i].lockPeriod && locks[i].amount > 0) {
                indexes[j] = i;
                j++;
            }
        }
        return indexes;
    }


    function rollover(uint index, uint newLockPeriod) external {
        lockInfo storage lock = userPositions[msg.sender][index];
        
        if (userPositions[msg.sender].length == 0) revert InsufficientBalance();
        if (lock.withdrawn) revert AlreadyWithdrawn();
        if (block.timestamp < lockStartTime[msg.sender][index] + lock.lockPeriod) revert StillLockedPeriod();
        if (lock.amount == 0) revert ZeroAmount();
        if (newLockPeriod <= block.timestamp) revert InvalidAmount();

        lock.withdrawn = true;
        
        uint256 newPositionIndex = userPositions[msg.sender].length;
        lockStartTime[msg.sender][newPositionIndex] = block.timestamp;
        
        userPositions[msg.sender].push(lockInfo({
            amount: lock.amount,
            lockPeriod: newLockPeriod,
            pendingReward: reward._calculateReward(lock.amount, newLockPeriod),
            claimedReward: 0,
            withdrawn: false,
            claimed: false
        }));


        emit MarketRolledOver(msg.sender, lock.amount, newLockPeriod);
    }

    function updateClaimedStatus(address user, uint256 positionIndex, uint256 claimedAmount) external {
        if (msg.sender != rewardAddress) revert Unauthorized();
        if (positionIndex >= userPositions[user].length) revert InvalidAmount();
        
        lockInfo storage position = userPositions[user][positionIndex];
        if (position.claimed) revert InvalidClaimedStatus();
        
        position.claimed = true;
        position.claimedReward += claimedAmount;
    }

}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {lockInfo} from "./types/Type.sol";

contract Market is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    IERC20 public asset;
    string public marketName;
    uint256 public tvl;
    uint256 public maxSupply;
    uint256 public constant APY_PRECISION = 100e2;

    mapping(uint256 => uint256) public rewardRates;
    mapping(bytes32 => lockInfo) public positions;
    mapping(address => bytes32[]) public userPositions;
    mapping(bytes32 => address) public positionOwner;

    event Deposit(address indexed receiver, bytes32 id, uint256 amount, uint256 unlockTime, uint256 reward);
    event Redeem(address indexed to, uint256 amount, uint256 reward);
    event DepositAsOwner(uint256 amount);
    event WithdrawToOwner(address indexed from, address indexed to, uint256 amount);
    event MarketRolledOver(address indexed user, uint256 amount, uint256 newLockPeriod);
    event DepositReward(address indexed user, uint256 amount);
    event WithdrawReward(address indexed user, uint256 amount);
    event RewardRateSet(uint256 lockPeriod, uint256 rateApy);

    error TokenNotAccepted();
    error MaxSupplyExceeded();
    error InvalidMaxSupply();
    error InvalidLockPeriod();
    error InsufficientBalance();
    error StillLockedPeriod();
    error ZeroAmount();
    error AlreadyWithdrawn();
    error InvalidUserPositions();
    error InvalidClaimedStatus();
    error Unauthorized();
    error ZeroTVL();

    constructor() {
        _disableInitializers();
    }

    function initialize(string memory _marketName, address _asset, uint256 _maxSupply) public initializer {
        if (msg.sender == address(0)) revert ZeroAmount();
        if (bytes(_marketName).length == 0) revert ZeroAmount();
        if (_asset == address(0)) revert ZeroAmount();
        if (_maxSupply == 0) revert InvalidMaxSupply();

        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        marketName = _marketName;
        asset = IERC20(_asset);
        maxSupply = _maxSupply;
    }

    function stake(address receiver, uint256 amount, uint256 lockPeriod) external nonReentrant returns (bytes32) {
        if (IERC20(asset).balanceOf(msg.sender) < amount) revert InsufficientBalance();
        if (asset != asset) revert TokenNotAccepted();
        if (tvl + amount > maxSupply) revert MaxSupplyExceeded();
        if (rewardRates[lockPeriod] == 0) revert InvalidLockPeriod();

        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        uint256 rateApy = rewardRates[lockPeriod];
        uint256 pendingReward = calculateReward(rateApy, amount, lockPeriod);
        bytes32 userKey = keccak256(abi.encodePacked(receiver, amount, lockPeriod, block.timestamp));
        userPositions[receiver].push(userKey);
        positionOwner[userKey] = receiver;

        uint256 _unlockTime = block.timestamp + lockPeriod;
        positions[userKey] =
            lockInfo({amount: amount, lockPeriod: lockPeriod, unlockTime: _unlockTime, reward: pendingReward});

        tvl += amount;

        emit Deposit(receiver, userKey, amount, _unlockTime, pendingReward);

        return userKey;
    }

    function redeem(bytes32 id) external nonReentrant returns (uint256) {
        if (positionOwner[id] != msg.sender) revert Unauthorized();

        lockInfo storage lock = positions[id];
        if (block.timestamp < lock.unlockTime) revert StillLockedPeriod();
        if (lock.amount == 0) revert ZeroAmount();
        if (asset.balanceOf(address(this)) < lock.amount + lock.reward) revert InsufficientBalance();

        lock.amount = 0;
        tvl -= lock.amount;
        asset.transfer(msg.sender, lock.amount + lock.reward);

        emit Redeem(msg.sender, lock.amount, lock.reward);

        return lock.amount + lock.reward;
    }

    function rollover(bytes32 id, uint256 newLockPeriod) external nonReentrant returns (bytes32) {
        if (positionOwner[id] != msg.sender) revert Unauthorized();
        
        lockInfo storage lock = positions[id];
        if (block.timestamp < lock.unlockTime) revert StillLockedPeriod();
        if (lock.amount == 0) revert ZeroAmount();
        if (newLockPeriod <= block.timestamp) revert InvalidLockPeriod();

        uint256 rateApy = rewardRates[newLockPeriod];
        uint256 pendingReward = calculateReward(rateApy, lock.amount, newLockPeriod);

        bytes32 userKey = keccak256(abi.encodePacked(msg.sender, lock.amount, newLockPeriod, block.timestamp));
        userPositions[msg.sender].push(userKey);

        positions[userKey] = lockInfo({
            amount: lock.amount + lock.reward,
            lockPeriod: newLockPeriod,
            unlockTime: block.timestamp + newLockPeriod,
            reward: pendingReward
        });

        lock.amount = 0;
        lock.reward = 0;
        tvl += lock.reward;

        emit MarketRolledOver(msg.sender, lock.amount, newLockPeriod);

        return userKey;
    }

    function setMaxSupply(uint256 _maxSupply) external onlyOwner {
        if (_maxSupply == 0) revert InvalidMaxSupply();
        if (_maxSupply < tvl) revert MaxSupplyExceeded();

        maxSupply = _maxSupply;
    }

    function depositAsOwner(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (asset.balanceOf(msg.sender) < amount) revert InsufficientBalance();

        asset.transferFrom(msg.sender, address(this), amount);
        emit DepositAsOwner(amount);
    }

    function withdrawToOwner(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (amount > asset.balanceOf(address(this))) revert InsufficientBalance();

        asset.transfer(msg.sender, amount);
        emit WithdrawToOwner(address(this), msg.sender, amount);
    }

    function addReward(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (asset.balanceOf(msg.sender) < amount) revert InsufficientBalance();
        if (tvl == 0) revert ZeroTVL();

        asset.transferFrom(msg.sender, address(this), amount);

        emit DepositReward(msg.sender, amount);
    }

    function removeReward(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (asset.balanceOf(address(this)) < amount) revert InsufficientBalance();

        asset.transfer(msg.sender, amount);
        emit WithdrawReward(msg.sender, amount);
    }

    function setRewardRate(uint256 lockPeriod, uint256 rateApy) external onlyOwner {
        rewardRates[lockPeriod] = rateApy;

        emit RewardRateSet(lockPeriod, rateApy);
    }

    function calculateReward(uint256 apy, uint256 amount, uint256 lockPeriod) public pure returns (uint256) {
        uint256 reward = (amount * apy * lockPeriod) / (365 days * APY_PRECISION);

        return reward;
    }

    function balanceOf(address account) external view returns (uint256) {
        uint256 totalBalance = 0;
        bytes32[] storage userKeys = userPositions[account];

        for (uint256 i = 0; i < userKeys.length; i++) {
            lockInfo storage lock = positions[userKeys[i]];
            totalBalance += lock.amount;
        }

        return totalBalance;
    }

    function rewardOf(address account) external view returns (uint256) {
        uint256 totalReward = 0;
        bytes32[] storage userKeys = userPositions[account];

        for (uint256 i = 0; i < userKeys.length; i++) {
            lockInfo storage lock = positions[userKeys[i]];
            totalReward += lock.reward;
        }

        return totalReward;
    }
}

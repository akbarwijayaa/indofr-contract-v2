// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Market} from "../src/Market.sol";
import {Reward} from "../src/Reward.sol";
import {MockUSDT} from "../src/mocks/MockUSDT.sol";
import {lockInfo} from "../src/types/StructType.sol";

contract MarketTest is Test {
    Market public market;
    Reward public reward;
    MockUSDT public usdt;
    MockUSDT public otherToken;

    address public owner = address(0x123);
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public attacker = address(0x666);

    uint256 constant INITIAL_BALANCE = 10_000_000;
    uint256 constant MAX_SUPPLY = 1_000_000;
    uint256 constant ONE_MONTH = 30 days;
    uint256 constant THREE_MONTH = 90 days;
    uint256 constant SIX_MONTH = 180 days;
    uint256 constant ONE_YEAR = 365 days;

    event Deposit(address indexed to, uint256 amount);
    event Redeem(address indexed to, uint256 amount);
    event DepositAsOwner(uint256 amount);
    event WithdrawToOwner(address indexed from, address indexed to, uint256 amount);
    event MarketRolledOver(address indexed user, uint256 amount, uint256 newLockPeriod);

    function setUp() public {
        usdt = new MockUSDT();
        otherToken = new MockUSDT();

        vm.startPrank(owner);
        market = new Market("FR-A", address(usdt), MAX_SUPPLY);
        reward = Reward(market.rewardAddress());
        reward.setRewardRate(ONE_MONTH, 400);
        reward.setRewardRate(THREE_MONTH, 600);
        reward.setRewardRate(SIX_MONTH, 800);
        reward.setRewardRate(ONE_YEAR, 1000);
        vm.stopPrank();

        usdt.mint(alice, INITIAL_BALANCE);
        usdt.mint(bob, INITIAL_BALANCE);
        usdt.mint(charlie, INITIAL_BALANCE);
        usdt.mint(attacker, INITIAL_BALANCE);
        usdt.mint(owner, INITIAL_BALANCE);

        otherToken.mint(alice, INITIAL_BALANCE);
    }

    function testDeposit() public {
        vm.startPrank(alice);
        uint256 initialSupply = market.tvl();
        usdt.approve(address(market), 100);
        market.deposit(alice, address(usdt), 100, ONE_MONTH);

        assertEq(market.tvl(), initialSupply + 100);
        assertEq(market.balanceOf(alice), 100);
    }

    function testDepositWithIncorrectLockPeriod() public {
        vm.startPrank(alice);
        usdt.approve(address(market), 100);
        vm.expectRevert();
        market.deposit(alice, address(usdt), 100, 10 days);
    }

    function testRedeem() public {
        vm.startPrank(alice);
        usdt.approve(address(market), 100);
        market.deposit(alice, address(usdt), 100, ONE_MONTH);

        skip(ONE_MONTH);

        market.redeem(0);
        assertEq(market.balanceOf(alice), 0);
    }

    function testMaxSupplyExceeded() public {
        vm.startPrank(alice);
        usdt.approve(address(market), 2_000_000);
        vm.expectRevert();
        market.deposit(alice, address(usdt), 2_000_000, ONE_MONTH);
    }

    function testDepositMultipleTime() public {
        vm.startPrank(alice);
        usdt.approve(address(market), 500);
        market.deposit(alice, address(usdt), 100, ONE_MONTH);
        market.deposit(alice, address(usdt), 200, ONE_MONTH);

        assertEq(market.tvl(), 300);
        assertEq(market.balanceOf(alice), 300);
    }

    function testDepositMultipleTimeAndRedeem() public {
        vm.startPrank(alice);
        usdt.approve(address(market), 500);
        market.deposit(alice, address(usdt), 100, ONE_MONTH);
        market.deposit(alice, address(usdt), 200, ONE_MONTH);

        skip(ONE_MONTH);

        market.redeem(0);
        assertEq(market.balanceOf(alice), 200);

        market.redeem(1);
        assertEq(market.balanceOf(alice), 0);
    }

    function testDepositMultipleUserAndFindIndexForRedeem() public {
        vm.startPrank(alice);
        usdt.approve(address(market), 500);
        market.deposit(alice, address(usdt), 100, ONE_MONTH);
        market.deposit(alice, address(usdt), 200, ONE_MONTH);

        vm.stopPrank();
        vm.startPrank(bob);
        usdt.approve(address(market), 300);
        market.deposit(bob, address(usdt), 300, ONE_MONTH);
        vm.stopPrank();

        skip(ONE_MONTH);

        uint256 aliceLockCount = market.userLockCount(alice);
        uint256 bobLockCount = market.userLockCount(bob);

        assertEq(aliceLockCount, 2);
        assertEq(bobLockCount, 1);
    }

    function testGetRedeemableIndexes() public {
        vm.startPrank(alice);
        usdt.approve(address(market), 500);
        market.deposit(alice, address(usdt), 100, ONE_MONTH);
        market.deposit(alice, address(usdt), 200, THREE_MONTH);
        market.deposit(alice, address(usdt), 100, THREE_MONTH);
        market.deposit(alice, address(usdt), 100, ONE_MONTH);
        vm.stopPrank();

        vm.startPrank(bob);
        usdt.approve(address(market), 300);
        market.deposit(bob, address(usdt), 300, ONE_MONTH);

        skip(ONE_MONTH);

        uint256[] memory aliceRedeemableIndexes = market.getRedeemableIndexes(alice);
        assertEq(aliceRedeemableIndexes.length, 2);

        uint256[] memory bobRedeemableIndexes = market.getRedeemableIndexes(bob);
        assertEq(bobRedeemableIndexes.length, 1);
    }

    function testRollover() public {
        vm.startPrank(alice);
        usdt.approve(address(market), 100);
        market.deposit(alice, address(usdt), 100, ONE_MONTH);

        skip(ONE_MONTH);

        uint256[] memory redeemableIndexes = market.getRedeemableIndexes(alice);
        assertEq(redeemableIndexes.length, 1);

        market.rollover(redeemableIndexes[0], THREE_MONTH);
        assertEq(market.balanceOf(alice), 100);

        uint256 userLockCount = market.userLockCount(alice);
        assertEq(userLockCount, 2);

        (uint256 amount, uint256 lockPeriod,,,, bool withdrawn, bool claimed) = market.userPositions(alice, 1);

        assertEq(amount, 100);
        assertEq(lockPeriod, THREE_MONTH);
        assertEq(withdrawn, false);
        assertEq(claimed, false);
    }
}

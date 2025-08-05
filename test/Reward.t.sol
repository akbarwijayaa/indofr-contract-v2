// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Market} from "../src/Market.sol";
import {Reward} from "../src/Reward.sol";
import {MockUSDT} from "../src/mocks/MockUSDT.sol";

contract RewardTest is Test {
    Market public market;
    Reward public reward;
    MockUSDT public usdt;

    address public owner = address(0x123);
    address public alice = address(0x1);
    address public bob = address(0x2);

    uint256 constant ONE_MONTH = 30 days;
    uint256 constant THREE_MONTH = 90 days;
    uint256 constant SIX_MONTH = 180 days;
    uint256 constant ONE_YEAR = 365 days;

    function setUp() public {
        usdt = new MockUSDT();

        vm.startPrank(owner);
        market = new Market("FR-A", address(usdt), 1_000_000);

        reward = Reward(market.rewardAddress());
        reward.setRewardRate(ONE_MONTH, 400);
        reward.setRewardRate(THREE_MONTH, 600);
        reward.setRewardRate(SIX_MONTH, 800);
        reward.setRewardRate(ONE_YEAR, 1000);
        vm.stopPrank();

        usdt.mint(alice, 1_000_000);
        usdt.mint(bob, 1_000_000);
    }

    function testInitialOwner() public view {
        console.log("Market address:", address(market));
        console.log("Market owner:", market.owner());
        console.log("Reward contract address:", address(reward));
        console.log("Reward contract owner:", reward.owner());
        console.log(reward.rewardRates(ONE_MONTH));
        console.log(reward.rewardRates(THREE_MONTH));
        console.log(reward.rewardRates(SIX_MONTH));
    }

    function testInjectRewardWithNoTokensMinted() public {
        usdt.mint(owner, 1000);
        vm.startPrank(owner);
        usdt.approve(address(reward), 1000);
        vm.expectRevert();
        reward.depositReward(1000);
        vm.stopPrank();
        assertEq(usdt.balanceOf(address(reward)), 0);
    }

    function testDepositRewardWithIncorrectBalance() public {
        vm.startPrank(alice);
        usdt.approve(address(market), 100_000);
        market.deposit(alice, address(usdt), 100_000, ONE_MONTH);
        vm.stopPrank();

        uint256 pendingReward = reward.totalPromisedRewards();

        vm.startPrank(owner);
        usdt.approve(address(reward), pendingReward);
        vm.expectRevert();
        reward.depositReward(pendingReward);
        vm.stopPrank();
    }

    function testDepositReward() public {
        vm.startPrank(alice);
        usdt.approve(address(market), 100_000);
        market.deposit(alice, address(usdt), 100_000, ONE_MONTH);
        vm.stopPrank();

        uint256 userReward = reward.totalPromisedRewards();

        usdt.mint(owner, userReward);
        vm.startPrank(owner);
        usdt.approve(address(reward), userReward);
        reward.depositReward(userReward);
        vm.stopPrank();

        assertEq(usdt.balanceOf(address(reward)), userReward);
        assertEq(reward.totalPromisedRewards(), userReward);
    }

    function testRewardFlowConsistent() public {
        vm.startPrank(alice);
        usdt.approve(address(market), 50_000);
        market.deposit(alice, address(usdt), 50_000, ONE_MONTH);
        vm.stopPrank();

        skip(ONE_MONTH);

        uint256 pendingReward = reward.calculateUserReward(50_000, ONE_MONTH);
        uint256 rewardBalanceBefore = reward.totalPromisedRewards();

        assertEq(rewardBalanceBefore, pendingReward);

        vm.startPrank(owner);
        usdt.mint(owner, pendingReward);
        usdt.approve(address(reward), pendingReward);
        reward.depositReward(pendingReward);
        vm.stopPrank();

        assertEq(reward.totalPromisedRewards(), rewardBalanceBefore);
        assertEq(usdt.balanceOf(address(reward)), pendingReward);

        vm.startPrank(alice);
        uint256 aliceBalanceBefore = usdt.balanceOf(alice);
        reward.claimReward(alice, 0);
        uint256 aliceBalanceAfter = usdt.balanceOf(alice);
        vm.stopPrank();

        assertEq(aliceBalanceAfter, aliceBalanceBefore + pendingReward);
        assertEq(reward.totalPromisedRewards(), 0);
    }

    function testClaimReward() public {
        vm.startPrank(alice);
        usdt.approve(address(market), 10_000);
        market.deposit(alice, address(usdt), 10_000, ONE_MONTH);
        vm.stopPrank();

        vm.startPrank(bob);
        usdt.approve(address(market), 10_000);
        market.deposit(bob, address(usdt), 10_000, ONE_MONTH);
        vm.stopPrank();

        skip(ONE_MONTH);

        uint256 userReward = reward.totalPromisedRewards();

        vm.startPrank(owner);
        usdt.mint(owner, userReward);
        usdt.approve(address(reward), userReward);
        reward.depositReward(userReward);
        vm.stopPrank();
        assertEq(usdt.balanceOf(address(reward)), userReward);
        assertEq(reward.totalPromisedRewards(), userReward);

        vm.startPrank(alice);
        uint256 aliceReward = reward.calculateUserReward(10_000, ONE_MONTH);
        uint256 aliceBalanceBefore = usdt.balanceOf(alice);

        reward.claimReward(alice, 0);
        uint256 aliceBalanceAfter = usdt.balanceOf(alice);
        assertEq(aliceBalanceAfter, aliceBalanceBefore + aliceReward);
    }

    function testClaimRewardMultipleUsers() public {
        vm.startPrank(alice);
        usdt.approve(address(market), 10_000);
        market.deposit(alice, address(usdt), 10_000, ONE_MONTH);
        vm.stopPrank();

        vm.startPrank(bob);
        usdt.approve(address(market), 20_000);
        market.deposit(bob, address(usdt), 20_000, ONE_MONTH);
        vm.stopPrank();

        skip(ONE_MONTH);

        uint256 totalRewards = reward.totalPromisedRewards();

        vm.startPrank(owner);
        usdt.mint(owner, totalRewards);
        usdt.approve(address(reward), totalRewards);
        reward.depositReward(totalRewards);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 aliceReward = reward.calculateUserReward(10_000, ONE_MONTH);
        uint256 aliceBalanceBefore = usdt.balanceOf(alice);

        reward.claimReward(alice, 0);
        uint256 aliceBalanceAfter = usdt.balanceOf(alice);
        assertEq(aliceBalanceAfter, aliceBalanceBefore + aliceReward);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 bobReward = reward.calculateUserReward(20_000, ONE_MONTH);
        uint256 bobBalanceBefore = usdt.balanceOf(bob);

        reward.claimReward(bob, 0);
        uint256 bobBalanceAfter = usdt.balanceOf(bob);
        assertEq(bobBalanceAfter, bobBalanceBefore + bobReward);
    }
}

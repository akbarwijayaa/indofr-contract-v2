// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import { Market } from "../src/Market.sol";
import { MockUSDT } from "../src/mocks/MockUSDT.sol";


contract MarketTest is Test {
    Market public market;
    MockUSDT public usdt;

    struct lockInfo {
        uint256 amount;
        uint256 lockPeriod;
        bool withdrawn;
        bool claimed;
    }

    address public owner = address(0x123);
    address public alice = address(0x1);
    address public bob = address(0x2);

    error MaxSupplyExceeded(uint256 maxSupply, uint256 attempted);

    function setUp() public {
        usdt = new MockUSDT();

        vm.startPrank(owner);
        market = new Market(
            "FR-A",
            address(usdt),
            1_000_000
        );
        vm.stopPrank();

        usdt.mint(alice, 1_000_000);
        usdt.mint(bob, 1_000_000);
    }

    function testDeposit() public {
        vm.startPrank(alice);
        uint256 initialSupply = market.tvl();
        usdt.approve(address(market), 100);
        market.deposit(alice, address(usdt), 100, 30 days);

        assertEq(market.tvl(), initialSupply + 100);
        assertEq(market.balanceOf(alice), 100);
    }

    function testRedeem() public {
        vm.startPrank(alice);
        usdt.approve(address(market), 100);
        market.deposit(alice, address(usdt), 100, 30 days);

        skip(30 days);

        market.redeem(0);
        assertEq(market.balanceOf(alice), 0);
    }

    function testMaxSupplyExceeded() public {
        vm.startPrank(alice);
        usdt.approve(address(market), 2_000_000);
        vm.expectRevert();
        market.deposit(alice, address(usdt), 2_000_000, 30 days);
    }

    function testDepositMultipleTime() public {
        vm.startPrank(alice);
        usdt.approve(address(market), 500);
        market.deposit(alice, address(usdt), 100, 30 days);
        market.deposit(alice, address(usdt), 200, 30 days);

        assertEq(market.tvl(), 300);
        assertEq(market.balanceOf(alice), 300);
    }

    function testDepositMultipleTimeAndRedeem() public {
        vm.startPrank(alice);
        usdt.approve(address(market), 500);
        market.deposit(alice, address(usdt), 100, 30 days);
        market.deposit(alice, address(usdt), 200, 30 days);

        skip(30 days);

        market.redeem(0);
        assertEq(market.balanceOf(alice), 200);

        market.redeem(1);
        assertEq(market.balanceOf(alice), 0);
    }

    function testDepositMultipleUserAndFindIndexForRedeem() public {
        vm.startPrank(alice);
        usdt.approve(address(market), 500);
        market.deposit(alice, address(usdt), 100, 30 days);
        market.deposit(alice, address(usdt), 200, 30 days);

        vm.stopPrank();
        vm.startPrank(bob);
        usdt.approve(address(market), 300);
        market.deposit(bob, address(usdt), 300, 30 days);
        vm.stopPrank();

        skip(30 days);

        uint256 aliceLockCount = market.userLockCount(alice);
        uint256 bobLockCount = market.userLockCount(bob);

        assertEq(aliceLockCount, 2);
        assertEq(bobLockCount, 1);
    }

    function testGetRedeemableIndexes() public {
        vm.startPrank(alice);
        usdt.approve(address(market), 500);
        market.deposit(alice, address(usdt), 100, 30 days);
        market.deposit(alice, address(usdt), 200, 60 days);
        market.deposit(alice, address(usdt), 100, 60 days);
        market.deposit(alice, address(usdt), 100, 30 days);
        vm.stopPrank();

        vm.startPrank(bob);
        usdt.approve(address(market), 300);
        market.deposit(bob, address(usdt), 300, 30 days);

        skip(30 days);

        uint256[] memory aliceRedeemableIndexes = market.getRedeemableIndexes(alice);
        assertEq(aliceRedeemableIndexes.length, 2);

        uint256[] memory bobRedeemableIndexes = market.getRedeemableIndexes(bob);
        assertEq(bobRedeemableIndexes.length, 1);

    }

    function testRollover() public {
        vm.startPrank(alice);
        usdt.approve(address(market), 100);
        market.deposit(alice, address(usdt), 100, 30 days);

        skip(30 days);

        uint256[] memory redeemableIndexes = market.getRedeemableIndexes(alice);
        assertEq(redeemableIndexes.length, 1);

        market.rollover(redeemableIndexes[0], 60 days);
        assertEq(market.balanceOf(alice), 100);

        uint256 userLockCount = market.userLockCount(alice);
        assertEq(userLockCount, 2);

        (
            uint256 amount,
            uint256 lockPeriod,
            ,
            ,
            bool withdrawn,
            bool claimed
        ) = market.userPositions(alice, 1);

        assertEq(amount, 100);
        assertEq(lockPeriod, 60 days);
        assertEq(withdrawn, false);
        assertEq(claimed, false);
    }

}

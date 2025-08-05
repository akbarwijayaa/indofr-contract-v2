// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Market} from "../src/Market.sol";
import {MockUSDT} from "../src/mocks/MockUSDT.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {lockInfo} from "../src/types/Type.sol";

contract MarketTest is Test {
    Market public market;
    MockUSDT public usdt;
    MockUSDT public otherToken;
    ProxyAdmin public admin;
    TransparentUpgradeableProxy public marketProxy;

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

    uint256 constant ONE_MONTH_APY = 400;
    uint256 constant THREE_MONTH_APY = 600;
    uint256 constant SIX_MONTH_APY = 800;
    uint256 constant ONE_YEAR_APY = 1000;

    event Deposit(address indexed to, uint256 amount);
    event Redeem(address indexed to, uint256 amount);
    event DepositAsOwner(uint256 amount);
    event WithdrawToOwner(address indexed from, address indexed to, uint256 amount);
    event MarketRolledOver(address indexed user, uint256 amount, uint256 newLockPeriod);

    function setUp() public {
        usdt = new MockUSDT();
        otherToken = new MockUSDT();

        vm.startPrank(owner);
        Market marketImplementation = new Market();
        console.log("Market Implementation deployed at:", address(marketImplementation));

        admin = new ProxyAdmin(msg.sender);
        marketProxy = new TransparentUpgradeableProxy(
            address(marketImplementation),
            address(admin),
            abi.encodeWithSelector(Market.initialize.selector, "FR-A", address(usdt), MAX_SUPPLY)
        );

        Market(address(marketProxy)).setRewardRate(ONE_MONTH, ONE_MONTH_APY);
        Market(address(marketProxy)).setRewardRate(THREE_MONTH, THREE_MONTH_APY);
        Market(address(marketProxy)).setRewardRate(SIX_MONTH, SIX_MONTH_APY);
        Market(address(marketProxy)).setRewardRate(ONE_YEAR, ONE_YEAR_APY);

        console.log("Reward rates set!");
        vm.stopPrank();

        usdt.mint(alice, INITIAL_BALANCE);
        usdt.mint(bob, INITIAL_BALANCE);
        usdt.mint(charlie, INITIAL_BALANCE);
        usdt.mint(attacker, INITIAL_BALANCE);
        usdt.mint(owner, INITIAL_BALANCE);

        otherToken.mint(alice, INITIAL_BALANCE);
    }

    function testDepositAsset() public {
        vm.startPrank(alice);
        uint256 initialSupply = Market(address(marketProxy)).tvl();
        usdt.approve(address(marketProxy), 100);
        Market(address(marketProxy)).stake(alice, 100, ONE_MONTH);

        assertEq(Market(address(marketProxy)).tvl(), initialSupply + 100);
        assertEq(Market(address(marketProxy)).balanceOf(address(alice)), 100);
    }

    function testDepositWithIncorrectLockPeriod() public {
        vm.startPrank(alice);
        usdt.approve(address(marketProxy), 100);
        vm.expectRevert();
        Market(address(marketProxy)).stake(alice, 100, 10 days);
    }

    function testRedeem() public {
        vm.startPrank(alice);
        usdt.approve(address(marketProxy), 100);
        bytes32 id = Market(address(marketProxy)).stake(alice, 100, ONE_MONTH);

        skip(ONE_MONTH);
        uint256 initialBalance = usdt.balanceOf(alice);

        uint256 claimedAmount = Market(address(marketProxy)).redeem(id);

        assertEq(claimedAmount + initialBalance, usdt.balanceOf(alice));
        assertEq(Market(address(marketProxy)).balanceOf(alice), 0);
    }

    function testMaxSupplyExceeded() public {
        vm.startPrank(alice);
        usdt.approve(address(marketProxy), 2_000_000);
        vm.expectRevert();
        Market(address(marketProxy)).stake(alice, 2_000_000, ONE_MONTH);
    }

    function testDepositMultipleTime() public {
        vm.startPrank(alice);
        usdt.approve(address(marketProxy), 500);
        Market(address(marketProxy)).stake(alice, 100, ONE_MONTH);
        Market(address(marketProxy)).stake(alice, 200, ONE_MONTH);

        assertEq(Market(address(marketProxy)).tvl(), 300);
        assertEq(Market(address(marketProxy)).balanceOf(alice), 300);
    }

    function testDepositMultipleTimeAndRedeem() public {
        vm.startPrank(alice);
        usdt.approve(address(marketProxy), 500);
        bytes32 id1 = Market(address(marketProxy)).stake(alice, 100, ONE_MONTH);
        bytes32 id2 = Market(address(marketProxy)).stake(alice, 200, ONE_MONTH);

        skip(ONE_MONTH);

        Market(address(marketProxy)).redeem(id1);
        assertEq(Market(address(marketProxy)).balanceOf(alice), 200);

        Market(address(marketProxy)).redeem(id2);
        assertEq(Market(address(marketProxy)).balanceOf(alice), 0);
    }

    function testRedeemWithNonOwner() public {
        vm.startPrank(alice);
        usdt.approve(address(marketProxy), 100);
        bytes32 id = Market(address(marketProxy)).stake(alice, 100, ONE_MONTH);

        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert();
        Market(address(marketProxy)).redeem(id);
    }

    function testRollover() public {
        vm.startPrank(alice);
        usdt.approve(address(marketProxy), 100);
        bytes32 id = Market(address(marketProxy)).stake(alice, 100, ONE_MONTH);
        (uint256 amountDeposited,,, uint256 rewardDeposited) = Market(address(marketProxy)).positions(id);
        assertEq(Market(address(marketProxy)).balanceOf(alice), 100);

        skip(ONE_MONTH);

        bytes32 idRollover = Market(address(marketProxy)).rollover(id, THREE_MONTH);
        assertEq(Market(address(marketProxy)).balanceOf(alice), amountDeposited + rewardDeposited);

        (uint256 amount, uint256 lockPeriod, uint256 unlockTime, uint256 reward) =
            Market(address(marketProxy)).positions(idRollover);

        assertEq(amount, amountDeposited + rewardDeposited);
        assertEq(lockPeriod, THREE_MONTH);
        assertEq(unlockTime, block.timestamp + THREE_MONTH);
        assertEq(reward, Market(address(marketProxy)).calculateReward(THREE_MONTH_APY, 100, THREE_MONTH));
    }

    // Reward Functions Tests

    function testInjectRewardWithNoTokensMinted() public {
        usdt.mint(owner, 1000);
        vm.startPrank(owner);
        usdt.approve(address(marketProxy), 1000);
        vm.expectRevert();
        Market(address(marketProxy)).addReward(1000);
        vm.stopPrank();
        assertEq(usdt.balanceOf(address(marketProxy)), 0);
    }

    function testDepositRewardWithIncorrectBalance() public {
        vm.startPrank(alice);
        usdt.approve(address(marketProxy), 100_000);
        Market(address(marketProxy)).stake(alice, 100_000, ONE_MONTH);
        vm.stopPrank();

        vm.startPrank(owner);
        usdt.approve(address(marketProxy), 100);
        vm.expectRevert();
        Market(address(marketProxy)).addReward(0);
        vm.stopPrank();
    }

    function testDepositReward() public {
        vm.startPrank(alice);
        usdt.approve(address(marketProxy), 100_000);
        Market(address(marketProxy)).stake(alice, 100_000, ONE_MONTH);
        vm.stopPrank();

        usdt.mint(owner, 100_000);
        vm.startPrank(owner);
        usdt.approve(address(marketProxy), 100_000);
        Market(address(marketProxy)).addReward(100_000);
        vm.stopPrank();

        assertEq(usdt.balanceOf(address(marketProxy)), 200_000);
    }

    function testClaimRewardMultipleUsers() public {
        vm.startPrank(alice);
        usdt.approve(address(marketProxy), 10_000);
        bytes32 idAlice = Market(address(marketProxy)).stake(alice, 10_000, ONE_MONTH);
        vm.stopPrank();

        vm.startPrank(bob);
        usdt.approve(address(marketProxy), 20_000);
        bytes32 idBob = Market(address(marketProxy)).stake(bob, 20_000, ONE_MONTH);
        vm.stopPrank();

        skip(ONE_MONTH);

        vm.startPrank(owner);
        usdt.mint(owner, 100_000);
        usdt.approve(address(marketProxy), 100_000);
        Market(address(marketProxy)).addReward(100_000);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 aliceBalanceBefore = usdt.balanceOf(alice);
        uint256 amountOutAlice = Market(address(marketProxy)).redeem(idAlice);
        assertEq(usdt.balanceOf(alice), aliceBalanceBefore + amountOutAlice);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 bobBalanceBefore = usdt.balanceOf(bob);
        uint256 amountOutBob = Market(address(marketProxy)).redeem(idBob);
        assertEq(usdt.balanceOf(bob), bobBalanceBefore + amountOutBob);
    }
}

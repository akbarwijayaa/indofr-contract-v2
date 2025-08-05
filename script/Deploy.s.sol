// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Market} from "../src/Market.sol";
import {MockUSDT} from "../src/mocks/MockUSDT.sol";

contract Deploy is Script {
    string MARKET_NAME = "FR-A";
    uint256 constant MAX_SUPPLY = 1_000_000;

    uint256 constant ONE_MONTH = 30 days;
    uint256 constant THREE_MONTH = 90 days;
    uint256 constant SIX_MONTH = 180 days;
    uint256 constant ONE_YEAR = 365 days;

    uint256 constant ONE_MONTH_APY = 400;
    uint256 constant THREE_MONTH_APY = 600;
    uint256 constant SIX_MONTH_APY = 800;
    uint256 constant ONE_YEAR_APY = 1000;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MockUSDT usdt = new MockUSDT();
        console.log("MockUSDT deployed at:", address(usdt));

        Market marketImplementation = new Market();
        console.log("Market Implementation deployed at:", address(marketImplementation));

        ProxyAdmin admin = new ProxyAdmin(msg.sender);

        TransparentUpgradeableProxy marketProxy = new TransparentUpgradeableProxy(
            address(marketImplementation),
            address(admin),
            abi.encodeWithSelector(Market.initialize.selector, MARKET_NAME, address(usdt), MAX_SUPPLY)
        );

        Market(address(marketProxy)).setRewardRate(ONE_MONTH, 400);
        Market(address(marketProxy)).setRewardRate(THREE_MONTH, 600);
        Market(address(marketProxy)).setRewardRate(SIX_MONTH, 800);
        Market(address(marketProxy)).setRewardRate(ONE_YEAR, 1000);

        console.log("Reward rates set!");

        vm.stopBroadcast();
    }
}

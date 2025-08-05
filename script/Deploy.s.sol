// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Market} from "../src/Market.sol";
import {Reward} from "../src/Reward.sol";
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

        Market market = new Market(MARKET_NAME, address(usdt), MAX_SUPPLY);
        console.log("Market deployed at:", address(market));

        Reward reward = new Reward(address(usdt), address(market), address(this));
        console.log("Reward contract address:", address(reward));

        reward.setRewardRate(ONE_MONTH, ONE_MONTH_APY);
        reward.setRewardRate(THREE_MONTH, THREE_MONTH_APY);
        reward.setRewardRate(SIX_MONTH, SIX_MONTH_APY);
        reward.setRewardRate(ONE_YEAR, ONE_YEAR_APY);

        console.log("Reward rates set!");

        vm.stopBroadcast();
    }
}

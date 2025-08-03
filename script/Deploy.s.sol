// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { Market } from "../src/Market.sol";
import { Reward } from "../src/Reward.sol";
import { MockUSDT } from "../src/mocks/MockUSDT.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MockUSDT usdt = new MockUSDT();
        console.log("MockUSDT deployed at:", address(usdt));

        Market market = new Market(
            "FR-A",
            address(usdt),
            1_000_000
        );
        console.log("Market deployed at:", address(market));

        Reward reward = new Reward(address(usdt), address(market), address(this));
        console.log("Reward contract address:", address(reward));


        vm.stopBroadcast();
    }
}
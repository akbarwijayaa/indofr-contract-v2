// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";


contract DeployTest is Test {
    Deploy public deploy;

    function setUp() public {
        deploy = new Deploy();
    }

    function testDeployment() public {
        deploy.run();
        console.log("Deployment script executed successfully.");
    }

}
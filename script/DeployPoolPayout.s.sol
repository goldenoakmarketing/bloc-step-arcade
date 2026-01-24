// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {PoolPayout} from "../src/PoolPayout.sol";

/**
 * @title DeployPoolPayout
 * @notice Deployment script for PoolPayout contract
 * @dev Run with: forge script script/DeployPoolPayout.s.sol:DeployPoolPayout --rpc-url https://mainnet.base.org --broadcast --verify
 */
contract DeployPoolPayout is Script {
    // Base Mainnet BLOC token
    address constant BLOC_TOKEN = 0x022c6cb9Fd69A99cF030cB43e3c28BF82bF68Fe9;
    // Owner address
    address constant OWNER = 0x2810A8d46B12341425ed33da6238A66E5A8afD55;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying PoolPayout...");
        console.log("BLOC Token:", BLOC_TOKEN);
        console.log("Owner:", OWNER);

        PoolPayout poolPayout = new PoolPayout(BLOC_TOKEN, OWNER);

        console.log("PoolPayout deployed at:", address(poolPayout));

        vm.stopBroadcast();

        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        console.log("Network: Base Mainnet");
        console.log("PoolPayout:", address(poolPayout));
        console.log("BLOC Token:", BLOC_TOKEN);
        console.log("Owner:", OWNER);
        console.log("=========================================\n");
        console.log("\nNEXT STEPS:");
        console.log("1. Call setGameServer() with your game server address");
        console.log("2. Transfer 625,000 BLOC to fund the pool");
    }
}

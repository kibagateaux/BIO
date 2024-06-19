// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { BaseLaunchpadTest } from "./Base.t.sol";
import "forge-std/Test.sol";


contract LaunchpadMainnetTests is BaseLaunchpadTest {
    function setUp() public override {
        // Fork from specified block chain at block
        vm.createSelectFork("https://rpc.ankr.com/eth"); // , block_number);

        // Fund attacker contract
        // deal(EthereumTokens.USDC, address(attackContract), 1 * 10 ** 10);

        // Tokens to track during snapshotting
        // tokens.push(EthereumTokens.USDC);

        // setAlias(address(attackContract), "Attacker");

        console.log("\n>>> Initial conditions");
    }

    // function testAttack() public snapshot(address(attackContract), tokens) {
    //     attackContract.initializeAttack();
    // }
}

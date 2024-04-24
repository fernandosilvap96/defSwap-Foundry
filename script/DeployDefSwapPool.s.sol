// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {PoolFactory} from "../src/PoolFactory.sol";
import {DefSwapPool} from "../src/DefSwapPool.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DeployDefSwapPool is Script {
    address public constant DEF_TOKEN_MAINNET =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 public constant MAINNET_CHAIN_ID = 1;

    function run() public {
        vm.startBroadcast();
        if (block.chainid == MAINNET_CHAIN_ID) {
            new PoolFactory(DEF_TOKEN_MAINNET);
            // We are are not on mainnet, assume we are testing
        } else {
            ERC20Mock mockDefToken = new ERC20Mock();
            new PoolFactory(address(mockDefToken));
        }
        vm.stopBroadcast();
    }
}

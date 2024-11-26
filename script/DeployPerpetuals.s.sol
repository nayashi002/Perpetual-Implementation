// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Perpetuals} from "../src/Perpetuals.sol";

contract DeployPerpetuals is Script{
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    function run() external returns(Perpetuals,HelperConfig){
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        tokenAddresses = [config.weth,config.wbtc];
        priceFeedAddresses = [config.wethUsdPriceFeed,config.wbtcUsdPriceFeed];
        vm.startBroadcast(config.account);
        Perpetuals perpetual = new Perpetuals(tokenAddresses,priceFeedAddresses);
        vm.stopBroadcast();
        return (perpetual,helperConfig);
    }
}
    
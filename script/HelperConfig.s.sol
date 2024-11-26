// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

abstract contract CodeConstant{
    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8; 
    address public constant DEFAULT_ANVIL_KEY_ADDRESS = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
}

contract HelperConfig is Script,CodeConstant{
    error HelperConfig__InvalidChainId();
   struct NetworkConfig{
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    address account;
   }
   NetworkConfig public localNetworkConfig;
   mapping(uint256 chainId => NetworkConfig networkConfig) public networkConfigs;
   constructor(){
    networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();

   }
     function getConfigByChainId(uint256 chainId) public returns(NetworkConfig memory){
        if(networkConfigs[chainId].wethUsdPriceFeed != address(0)){
              return networkConfigs[chainId];
        }
        else if(chainId == LOCAL_CHAIN_ID){
             return getOrCreateAnvilChainId();
        }
        else{
            revert HelperConfig__InvalidChainId();
        }
    }
    function getConfig() public returns(NetworkConfig memory){
        return getConfigByChainId(block.chainid);
    }
    function getSepoliaEthConfig() public pure returns(NetworkConfig memory){
        return NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed:  0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            account: 0x78f891f23ad2F7b398D6f0191a4675C71e4E4cD6
        });
    }
    function getOrCreateAnvilChainId() public returns(NetworkConfig memory){
        if(localNetworkConfig.wethUsdPriceFeed != address(0)){
            return localNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS,ETH_USD_PRICE);
         ERC20Mock weth = new ERC20Mock();
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS,BTC_USD_PRICE);
            ERC20Mock wbtc = new ERC20Mock();
            vm.stopBroadcast();
            localNetworkConfig = NetworkConfig({
                wethUsdPriceFeed: address(ethUsdPriceFeed),
                wbtcUsdPriceFeed: address(btcUsdPriceFeed),
                weth: address(weth),
                wbtc: address(wbtc),
                account: DEFAULT_ANVIL_KEY_ADDRESS
            });
            return localNetworkConfig;
    }
}

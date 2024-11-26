// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test,console} from "forge-std/Test.sol";
import {Perpetuals} from "../src/Perpetuals.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {DeployPerpetuals} from "../script/DeployPerpetuals.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";

contract PerpetualsTest is Test{
    Perpetuals perpetual;
    HelperConfig helperConfig;
    DeployPerpetuals deployer;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    address account;
    address public  USER = makeAddr("user");
    address public  LP_PROVIDER = makeAddr("lp_provider");
    uint256 public constant AMOUNT_TO_DEPOSIT = 10 ether;
    uint256 public constant COLLATERAL_AMOUNT = 3 ether;
    uint256 public constant POSITION_SIZE = 4e18;
    event LiquidityProvided(address indexed provider, address indexed token, uint256 amount);
     event PositionOpened(address indexed user, uint256 size, bool isLong, address indexed token, uint256 collateralAmount);
    function setUp() external{
        deployer = new DeployPerpetuals();
        (perpetual,helperConfig) = deployer.run();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        wethUsdPriceFeed = config.wethUsdPriceFeed;
        wbtcUsdPriceFeed = config.wbtcUsdPriceFeed;
        weth = config.weth;
        wbtc = config.wbtc;
        account = config.account;
        ERC20Mock(weth).mint(USER,AMOUNT_TO_DEPOSIT);
        ERC20Mock(wbtc).mint(USER,COLLATERAL_AMOUNT);
        // ERC20Mock(weth).approve(address(perpetual),AMOUNT_TO_DEPOSIT);
        // ERC20Mock(wbtc).approve(address(perpetual),COLLATERAL_AMOUNT);
        ERC20Mock(weth).mint(LP_PROVIDER,100 ether);
        ERC20Mock(wbtc).mint(LP_PROVIDER,100 ether);
         vm.deal(USER,10 ether);
        vm.deal(LP_PROVIDER,10 ether);
    }
    // Price  test
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    function test_reverts_if_price_length_not_equal() public{
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        vm.expectRevert(Perpetuals.Perpetual__PriceFeedsNotSameLength.selector);
        new Perpetuals(tokenAddresses,priceFeedAddresses);
    }
          function testGetUsdValue() public view{
       uint256 ethAmount = 15e18;
         uint256 expectedUsd = 30000e18;
         uint256 actualUsd = perpetual.getUsdValue(ethAmount,weth);
         assertEq(expectedUsd,actualUsd);
      }
    function test_add_liquidity() public{
         vm.startPrank(LP_PROVIDER);
         ERC20Mock(weth).approve(address(perpetual),10 ether);
         perpetual.deposit(10 ether,weth);
         vm.stopPrank();
        
    }
    function test_revert_if_user_deposit_zero() public{
        vm.startPrank(LP_PROVIDER);
        ERC20Mock(weth).approve(address(perpetual),10 ether);
        vm.expectRevert(Perpetuals.Perpetual__AmountMustBeMoreThanZero.selector);
        perpetual.deposit(0,weth);
        vm.stopPrank();
    }
    function test_revertWhen_InvalidToken() public{
        vm.startPrank(LP_PROVIDER);
        vm.expectRevert(Perpetuals.Perpetual__NotAllowedToken.selector);
        perpetual.deposit(10 ether,address(0));
        vm.stopPrank();
    }
    function test_Emits_DepositEvent() public{
        vm.startPrank(LP_PROVIDER);
        ERC20Mock(weth).approve(address(perpetual),10 ether);
        vm.expectEmit(true,true,false,true);
        emit LiquidityProvided(LP_PROVIDER,weth,10 ether);
        perpetual.deposit(10 ether,weth);
        vm.stopPrank();
    }

    function test_withdraw_reverts_if_zero_Amount() public{
        vm.startPrank(LP_PROVIDER);
        vm.expectRevert(Perpetuals.Perpetual__AmountMustBeMoreThanZero.selector);
        perpetual.withdraw(0,weth);
        vm.stopPrank();
    }
    function test_withdraw_reverts_if_not_enough_liquidity() public{
        vm.startPrank(LP_PROVIDER);
        ERC20Mock(weth).approve(address(perpetual),AMOUNT_TO_DEPOSIT);
        perpetual.deposit(AMOUNT_TO_DEPOSIT,weth);
        uint256 doubled_liquidity = 2 * AMOUNT_TO_DEPOSIT;
        vm.expectRevert(Perpetuals.Perpetual__NotEnoughLiquidity.selector);
        perpetual.withdraw(doubled_liquidity,weth);
        vm.stopPrank();
    }
        function testWithdrawRevertsIfBelowReserveThreshold() public {
        // Setup: Deposit and open position to create reserve requirement
        vm.startPrank(LP_PROVIDER);
        ERC20Mock(weth).approve(address(perpetual), AMOUNT_TO_DEPOSIT);
        perpetual.deposit(AMOUNT_TO_DEPOSIT, weth);
        vm.stopPrank();

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(perpetual), COLLATERAL_AMOUNT);
        perpetual.openPosition(POSITION_SIZE, true, weth, COLLATERAL_AMOUNT);
        vm.stopPrank();

        // Try to withdraw more than allowed by reserve threshold
        vm.startPrank(LP_PROVIDER);
        uint256 maxWithdraw = (AMOUNT_TO_DEPOSIT * (200 - perpetual.LIQUIDITY_RESERVE_THRESHOLD())) / 100;
        vm.expectRevert(Perpetuals.Perpetual__NotEnoughLiquidity.selector);
        perpetual.withdraw(maxWithdraw + 1e18, weth);
        vm.stopPrank();
    }

    function test_successfull_withdraw() public{
        vm.startPrank(LP_PROVIDER);
        ERC20Mock(weth).approve(address(perpetual),AMOUNT_TO_DEPOSIT);
        perpetual.deposit(AMOUNT_TO_DEPOSIT,weth);
        uint256 withdrawAmount = AMOUNT_TO_DEPOSIT / 2;
        // uint256 initialBalance = ERC20Mock(weth).balanceOf(LP_PROVIDER);
        // uint256 initialLiquidity = perpetual.s_totalLiquidity();
        perpetual.withdraw(withdrawAmount,weth);
        vm.stopPrank();
    }
    function test_RevertWhen_OpenPosition_ZeroSize()public{
        vm.startPrank(USER);
        vm.expectRevert(Perpetuals.Perpetual__AmountMustBeMoreThanZero.selector);
        perpetual.openPosition(0,true,weth,COLLATERAL_AMOUNT);
        vm.stopPrank();
    }
       function test_RevertWhen_OpenPosition_ZeroCollateral() public {
        vm.startPrank(USER);
        vm.expectRevert(Perpetuals.Perpetual__AmountMustBeMoreThanZero.selector);
        perpetual.openPosition(POSITION_SIZE, true, weth, 0);
        vm.stopPrank();
    }
    function test_OpenPosition_Successfully() public {
    vm.startPrank(USER);
    
    uint256 depositAmount = 5e18;  // 5 ETH
    ERC20Mock(weth).approve(address(perpetual), depositAmount);
    perpetual.deposit(depositAmount, weth);
    
    // Check total liquidity in USD terms
    uint256 sizeInUsd = perpetual.getUsdValue(POSITION_SIZE, weth);
        uint256 collateralInUsd = perpetual.getUsdValue(COLLATERAL_AMOUNT, weth);
    uint256 expectedLiquidityInUsd = perpetual.getUsdValue(depositAmount, weth);
    assertEq(perpetual.s_totalLiquidity(), expectedLiquidityInUsd);
    uint256 leverage = (sizeInUsd * 1e18) / collateralInUsd;
    assertTrue(leverage <= perpetual.LEVERAGE__THRESHOLD() * 1e18, "Leverage too high");
    assertTrue(sizeInUsd <= perpetual.s_totalLiquidity(),"Size in USD is greater than total liquidity");
    ERC20Mock(weth).approve(address(perpetual), COLLATERAL_AMOUNT);
      perpetual.openPosition(POSITION_SIZE, true, weth, COLLATERAL_AMOUNT);
      (
        bool isOpen,
        uint256 size,
        uint256 collateral,
        bool isLong,
        address token,
        uint256 entryPrice
    ) = perpetual.s_positions(USER);
    
    assertTrue(isOpen, "Position should be open");
    assertEq(size, POSITION_SIZE, "Wrong position size");
    assertEq(collateral, COLLATERAL_AMOUNT, "Wrong collateral amount");
    assertTrue(isLong, "Should be long position");
    assertEq(token, weth, "Wrong token");
    assertGt(entryPrice, 0, "Entry price should be set");
    vm.stopPrank();
        // Verify position
       
        // vm.startPrank(USER);

        // // Get USD values before opening position
        
        
        // // Calculate leverage
    }
   ////////////////////////////
    // Increase Position Tests//
    //////////////////

    function test_cant_increase_position_when_not_opened() public{
        vm.startPrank(USER);
        vm.expectRevert(Perpetuals.Perpetual__PositionNotOpen.selector);
        perpetual.increasePositionSize(POSITION_SIZE);
        vm.stopPrank();
    }
    function test_cant_increase_collateral_when_not_opened() public {
    vm.startPrank(USER);
    
    // Try to increase collateral when no position exists
    vm.expectRevert(Perpetuals.Perpetual__PositionNotOpen.selector);
    perpetual.increasePositionCollateral(COLLATERAL_AMOUNT);
    
    vm.stopPrank();
}
modifier openPosition(){
   vm.startPrank(USER);
    
    uint256 depositAmount = 5e18;  // 5 ETH
    ERC20Mock(weth).approve(address(perpetual), depositAmount);
    perpetual.deposit(depositAmount, weth);
    
    // Check total liquidity in USD terms
    uint256 sizeInUsd = perpetual.getUsdValue(POSITION_SIZE, weth);
        uint256 collateralInUsd = perpetual.getUsdValue(COLLATERAL_AMOUNT, weth);
    uint256 expectedLiquidityInUsd = perpetual.getUsdValue(depositAmount, weth);
    assertEq(perpetual.s_totalLiquidity(), expectedLiquidityInUsd);
    uint256 leverage = (sizeInUsd * 1e18) / collateralInUsd;
    assertTrue(leverage <= perpetual.LEVERAGE__THRESHOLD() * 1e18, "Leverage too high");
    assertTrue(sizeInUsd <= perpetual.s_totalLiquidity(),"Size in USD is greater than total liquidity");
    ERC20Mock(weth).approve(address(perpetual), COLLATERAL_AMOUNT);
      perpetual.openPosition(POSITION_SIZE, true, weth, COLLATERAL_AMOUNT);
      (
        bool isOpen,
        uint256 size,
        uint256 collateral,
        bool isLong,
        address token,
        uint256 entryPrice
    ) = perpetual.s_positions(USER);
    _;
}
function test_increase_position_size_successfully() public openPosition{
    uint256 newSize = POSITION_SIZE + 1e10;
    perpetual.increasePositionSize(newSize);
}
function test_increase_collateral_successfully() public {
    vm.startPrank(LP_PROVIDER);
    ERC20Mock(weth).approve(address(perpetual),10 ether);
    perpetual.deposit(10 ether,weth);
    // Setup: First open a position
    vm.startPrank(USER);
    
    // Mint enough tokens for initial collateral and increase
    uint256 initialCollateral = 3e18;
    uint256 collateralIncrease = 2e18;
    uint256 totalNeeded = initialCollateral + collateralIncrease;
    
    // Mint tokens to user
    ERC20Mock(weth).mint(USER, totalNeeded);
    
    // Approve tokens for initial position
    ERC20Mock(weth).approve(address(perpetual), totalNeeded);
    
    // Open initial position
    perpetual.openPosition(POSITION_SIZE, true, weth, initialCollateral);
    
    // Get initial position details
    (bool isOpen, , uint256 collateralBefore,,, ) = perpetual.s_positions(USER);
    assertTrue(isOpen, "Position should be open");
    assertEq(collateralBefore, initialCollateral, "Initial collateral not set correctly");
    
    // Increase collateral
    perpetual.increasePositionCollateral(collateralIncrease);
    
    // Verify increased collateral
    (, , uint256 collateralAfter,,, ) = perpetual.s_positions(USER);
    assertEq(collateralAfter, initialCollateral + collateralIncrease, "Collateral not increased correctly");
    

    
    vm.stopPrank();
}
 function test_RevertWhen_ClosePosition_NotOpen() public {
        vm.startPrank(USER);
        vm.expectRevert(Perpetuals.Perpetual__PositionNotOpen.selector);
        perpetual.closePosition();
        vm.stopPrank();
    }
function test_ClosePosition_WithProfit() public {
    vm.startPrank(LP_PROVIDER);
    uint256 lpAmount = 1000e18; // Large amount of liquidity
    ERC20Mock(weth).mint(LP_PROVIDER, lpAmount);
    ERC20Mock(weth).approve(address(perpetual), lpAmount);
    perpetual.deposit(lpAmount, weth);
    vm.stopPrank();
        // Setup: Open a position first
        vm.startPrank(USER);
        uint256 initialBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 initialBalanceInUsd = perpetual.getUsdValue(initialBalance,weth);
        uint256 collateralAmount = 3e18;
        
        ERC20Mock(weth).approve(address(perpetual), collateralAmount);
        perpetual.openPosition(POSITION_SIZE, true, weth, collateralAmount);
        
        // Simulate price increase (100% increase)
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(400000000000); // $4000
        uint256 newBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 newBalanceInUsd = perpetual.getUsdValue(newBalance,weth);
        uint256 profit = newBalanceInUsd - initialBalanceInUsd;
        uint256 profitInTokens = perpetual.getTokenAmount(profit,weth);
        uint256 totalBalance = profitInTokens + initialBalance;
        console.log("profit",profit);
        // Close position
        perpetual.closePosition();
        
        // Verify position is closed
        (bool isOpen,,,,, ) = perpetual.s_positions(USER);
        assertFalse(isOpen, "Position should be closed");
        assertTrue(profit > 0, "Profit should be greater than 0");
        assertLt(ERC20Mock(weth).balanceOf(address(perpetual)), lpAmount);
        assertEq(ERC20Mock(weth).balanceOf(USER), totalBalance);
        
        vm.stopPrank();
    }
     function test_DecreasePosition_WithoutOpenPosition() public {
        vm.startPrank(USER);
        vm.expectRevert(Perpetuals.Perpetual__PositionNotOpen.selector);
        perpetual.decreasePositionSize(POSITION_SIZE);
        vm.stopPrank();
    }
    function test_closePosition_withNoProfit() public{
      vm.startPrank(LP_PROVIDER);
    uint256 lpAmount = 1000e18; // Large amount of liquidity
    ERC20Mock(weth).mint(LP_PROVIDER, lpAmount);
    ERC20Mock(weth).approve(address(perpetual), lpAmount);
    perpetual.deposit(lpAmount, weth);
    vm.stopPrank();
        // Setup: Open a position first
        vm.startPrank(USER);
        uint256 initialBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 initialBalanceInUsd = perpetual.getUsdValue(initialBalance,weth);
        uint256 collateralAmount = 3e18;
        
        ERC20Mock(weth).approve(address(perpetual), collateralAmount);
        perpetual.openPosition(POSITION_SIZE, true, weth, collateralAmount);
        
        // Simulate price increase (100% increase)
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(200000000000); // $2000
        perpetual.closePosition();
       assertEq(ERC20Mock(weth).balanceOf(USER), initialBalance); 
        // Verify position is closed
        (bool isOpen,,,,, ) = perpetual.s_positions(USER);
        vm.stopPrank();

    }
    function test_closePosition_withlost() public{
            vm.startPrank(LP_PROVIDER);
           uint256 lpAmount = 1000e18; // Large amount of liquidity
    ERC20Mock(weth).mint(LP_PROVIDER, lpAmount);
    ERC20Mock(weth).approve(address(perpetual), lpAmount);
    perpetual.deposit(lpAmount, weth);
    vm.stopPrank();
        // Setup: Open a position first
        vm.startPrank(USER);
        uint256 initialBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 initialBalanceInUsd = perpetual.getUsdValue(initialBalance,weth);
        uint256 collateralAmount = 3e18;
        
        ERC20Mock(weth).approve(address(perpetual), collateralAmount);
        perpetual.openPosition(POSITION_SIZE, true, weth, collateralAmount);
        
        // Simulate price increase (100% increase)
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(100000000000); // $1000
        perpetual.closePosition();
        uint256 newBalance = ERC20Mock(weth).balanceOf(USER);
       assertLt(newBalance, initialBalance);
        // Verify position is closed
        (bool isOpen,,,,, ) = perpetual.s_positions(USER);
        vm.stopPrank();
    }
    function test_DecreasePosition_RevertsIfInvalidAmount() public {
    // Setup: Open a position first
    vm.startPrank(LP_PROVIDER);
    uint256 lpAmount = 1000e18;
    ERC20Mock(weth).mint(LP_PROVIDER, lpAmount);
    ERC20Mock(weth).approve(address(perpetual), lpAmount);
    perpetual.deposit(lpAmount, weth);
    vm.stopPrank();

    vm.startPrank(USER);
    uint256 collateralAmount = 3e18;
    ERC20Mock(weth).approve(address(perpetual), collateralAmount);
    perpetual.openPosition(POSITION_SIZE, true, weth, collateralAmount);

    // Attempt to decrease by zero or more than the position size
    vm.expectRevert(Perpetuals.Perpetual__AmountMustBeMoreThanZero.selector);
    perpetual.decreasePositionSize(0);

    vm.expectRevert(Perpetuals.Perpetual__DecreasePositionInvalid.selector);
    perpetual.decreasePositionSize(POSITION_SIZE + 1);

    vm.stopPrank();
}
function test_DecreasePositionSize_Successfully() public {
    // Setup: Open a position
    vm.startPrank(LP_PROVIDER);
    uint256 lpAmount = 1000e18;
    ERC20Mock(weth).mint(LP_PROVIDER, lpAmount);
    ERC20Mock(weth).approve(address(perpetual), lpAmount);
    perpetual.deposit(lpAmount, weth);
    vm.stopPrank();

    vm.startPrank(USER);
    uint256 collateralAmount = 3e18;
    ERC20Mock(weth).approve(address(perpetual), collateralAmount);
    perpetual.openPosition(POSITION_SIZE, true, weth, collateralAmount);

    // Verify initial state
    (bool isOpen, uint256 initialSize, uint256 initialCollateral, , , ) = perpetual.s_positions(USER);
    assertTrue(isOpen, "Position should be open");
    assertEq(initialSize, POSITION_SIZE, "Initial position size mismatch");

    // Decrease position size
    uint256 decreaseAmount = 1e18;
    perpetual.decreasePositionSize(decreaseAmount);

    
    assertTrue(isOpen, "Position should still be open");
    vm.stopPrank();
}
function test_DecreasePositionSize_ToZero() public {
    // Setup: Open a position
    vm.startPrank(LP_PROVIDER);
    uint256 lpAmount = 1000e18;
    ERC20Mock(weth).mint(LP_PROVIDER, lpAmount);
    ERC20Mock(weth).approve(address(perpetual), lpAmount);
    perpetual.deposit(lpAmount, weth);
    vm.stopPrank();

    vm.startPrank(USER);
    uint256 collateralAmount = 3e18;
    ERC20Mock(weth).approve(address(perpetual), collateralAmount);
    perpetual.openPosition(POSITION_SIZE, true, weth, collateralAmount);

    // Decrease position size to zero
    uint256 collateralAmountInUSD = perpetual.getUsdValue(collateralAmount,weth);
       // Unpack position tuple
    (bool isOpen, uint256 size, uint256 collateral, bool isLong, address token, uint256 entryPrice) = perpetual.s_positions(USER);

    // Call updatePositionAfterDecrease
    perpetual.updatePositionAfterDecrease(
        Perpetuals.Position({
            isOpen: isOpen,
            size: size,
            collateral: collateral,
            isLong: isLong,
            token: token,
            entryPrice: entryPrice
        }),
        POSITION_SIZE,
        collateralAmountInUSD
    );
}
    

}
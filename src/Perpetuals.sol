// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "./oracle/AggregatorV3Interface.sol";
contract Perpetuals is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SignedMath for int256;
    
    //////////////////
    // Errors      //
    /////////////////
  error Perpetual__AmountMustBeMoreThanZero();
  error Perpetual__NotAllowedToken();
  error Perpetual__TransferFailed();
  error Perpetual__PriceFeedsNotSameLength();
  error Perpetual__NotEnoughLiquidity();
  error Perpetual__PositionAlreadyOpen();
  error Perpetual__LeverageTooHigh();
  error Perpetual__PositionNotOpen();
  error Perpetual__TokenMismatch();
  error Perpetual__DecreasePositionInvalid();
  error Perpetual__PositionNotLiquidatable();
  error Perpetual__UserCantLiquidateHimself();
  //////////////////
  // Structs     //
 struct Position {
        bool isOpen;
        uint256 size;         // Position size in USD
        uint256 collateral;   // Amount of collateral token
        bool isLong;       // Long = true, Short = false
        address token;        // Collateral token address
        uint256 entryPrice;   // Price when position was opened
    }
    //////////////////
    // State Variables //
    //////////////////
    uint256 public constant LIQUIDITY_PENALTY_FEE_PERCENTAGE = 10;
    uint256 public constant LIQUIDITY_RESERVE_THRESHOLD = 80;
    uint256 public constant LIQUIDITY_RESERVE_THRESHOLD_PRECISION = 100;
     uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 public constant LEVERAGE__THRESHOLD = 20;
    uint256 public s_totalLiquidity;
    mapping(address lpAddress => uint256 amountDeposited) public s_liquidityProviders;
    mapping(address tokenAddress => address priceFeedAddress) public s_priceFeeds;
    mapping(address user => Position) public s_positions;
  /////////////////
  // Events      //
  ///////////////// 
  event LiquidityProvided(address indexed provider, address indexed token, uint256 amount);
  event LiquidityWithdrawn(address indexed provider, address indexed token, uint256 amount);
  event PositionOpened(address indexed user, uint256 size, bool isLong, address indexed token, uint256 collateralAmount);
  event PositionIncreased(address indexed user, uint256 size, bool isLong, address indexed token, uint256 collateralAmount);
  event PositionClosed(address indexed user, uint256 size, bool isLong, address indexed token, uint256 collateralAmount);
  event PositionSizeDecreased(address indexed user, uint256 size, bool isLong, address indexed token, uint256 collateralAmount);
   event PositionLiquidated(address indexed user, address indexed liquidator, uint256 size, bool isLong, address indexed token, uint256 collateralAmount);
    //////////////////
    // Modifiers  ////
    /////////////////
    modifier onlyAllowedTokens(address _token){
        if(s_priceFeeds[_token] == address(0)){
            revert Perpetual__NotAllowedToken();
        }
        _;
    }
    modifier moreThanZero(uint256 _amount){
        if(_amount <= 0){
            revert Perpetual__AmountMustBeMoreThanZero();
        }
        _;
    }
    //////////////////
    // Constructor //
    /////////////////
    constructor(address[] memory _allowedTokens, address[] memory _priceFeeds){
        if(_allowedTokens.length != _priceFeeds.length){
            revert Perpetual__PriceFeedsNotSameLength();
        }
        for(uint256 i = 0; i < _allowedTokens.length; i++){
            s_priceFeeds[_allowedTokens[i]] = _priceFeeds[i];
        }
    }
    //////////////////
    // Functions   //
    /////////////////
    function deposit(uint256 amount, address _token) external moreThanZero(amount) onlyAllowedTokens(_token){
        uint256 amountInUsd = getUsdValue(amount,_token);
        s_liquidityProviders[msg.sender] += amountInUsd; 
        s_totalLiquidity += amountInUsd;
         IERC20(_token).safeTransferFrom(msg.sender,address(this),amount);
       
        emit LiquidityProvided(msg.sender,_token,amount);
    }

   function withdraw(uint256 _amount, address _token) external nonReentrant moreThanZero(_amount) onlyAllowedTokens(_token) {
    uint256 providerBalance = s_liquidityProviders[msg.sender];
    uint256 amountInUsd = getUsdValue(_amount,_token);  
    if(amountInUsd > providerBalance){
        revert Perpetual__NotEnoughLiquidity();
    }
    
    // Calculate current reserve threshold
    uint256 currentReserveThreshold = (s_totalLiquidity * LIQUIDITY_RESERVE_THRESHOLD) / LIQUIDITY_RESERVE_THRESHOLD_PRECISION;
    
    // Check if withdrawal would breach reserve
    if(s_totalLiquidity - _amount >= currentReserveThreshold) {
        s_liquidityProviders[msg.sender] -= _amount;
        s_totalLiquidity -= _amount;
        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit LiquidityWithdrawn(msg.sender, _token, _amount);
    } else {
        revert Perpetual__NotEnoughLiquidity();
    }
}
   function openPosition(
    uint256 _size,
    bool _isLong,
    address _token,
    uint256 _collateralAmount
) external moreThanZero(_size) moreThanZero(_collateralAmount) {
    // Initial checks
    if(s_positions[msg.sender].isOpen) 
        revert Perpetual__PositionAlreadyOpen();
    if(_size == 0 || _collateralAmount == 0) 
        revert Perpetual__AmountMustBeMoreThanZero();

    // Calculate values
    uint256 collateralUsdValue = getCollateralAmountInUsd(_collateralAmount, _token);
    uint256 sizeInUsd = getUsdValue(_size, _token);
    uint256 leverage = sizeInUsd * PRECISION / collateralUsdValue;
    uint256 sizeInTokens = getTokenAmount(sizeInUsd,_token);
    // Validation s
    if(sizeInTokens > s_totalLiquidity) 
        revert Perpetual__NotEnoughLiquidity();
    if(leverage > LEVERAGE__THRESHOLD * PRECISION) 
        revert Perpetual__LeverageTooHigh();

    // Transfer collateral
    IERC20(_token).safeTransferFrom(msg.sender, address(this), _collateralAmount);

    // Create position
    s_positions[msg.sender] = Position({
        isOpen: true,
        size: _size,
        collateral: _collateralAmount,
        isLong: _isLong,
        token: _token,
        entryPrice: getUsdValue(_size, _token)
    });

    emit PositionOpened(
        msg.sender,
        _size,
        _isLong,
        _token,
        _collateralAmount
    );
}
function increasePositionSize(
    uint256 _sizeAmount
) external moreThanZero(_sizeAmount) {
    // Check if position exists
    if(!s_positions[msg.sender].isOpen) 
        revert Perpetual__PositionNotOpen();

    // Calculate USD values
    uint256 sizeInUsd = getUsdValue(_sizeAmount, s_positions[msg.sender].token);
    uint256 sizeInTokens = getTokenAmount(sizeInUsd,s_positions[msg.sender].token);

    // Check liquidity
    if(sizeInTokens > s_totalLiquidity - s_positions[msg.sender].size) 
        revert Perpetual__NotEnoughLiquidity();

    // Update position
    s_positions[msg.sender].size += _sizeAmount;
    s_positions[msg.sender].entryPrice = getUsdValue(
        _sizeAmount,
        s_positions[msg.sender].token
    );

    // Emit event
    emit PositionIncreased(
        msg.sender,
        _sizeAmount,
        s_positions[msg.sender].isLong,
        s_positions[msg.sender].token,
        s_positions[msg.sender].collateral
    );
}
function increasePositionCollateral(uint256 _collateralAmount) public moreThanZero(_collateralAmount){
    if(!s_positions[msg.sender].isOpen) revert Perpetual__PositionNotOpen();
     s_positions[msg.sender].collateral += _collateralAmount;
     IERC20(s_positions[msg.sender].token).safeTransferFrom(msg.sender,address(this),_collateralAmount);
     emit PositionIncreased(msg.sender,_collateralAmount,s_positions[msg.sender].isLong,s_positions[msg.sender].token,s_positions[msg.sender].collateral);
}

 function calculatePnl(uint256 _size, address _token, address user) public view returns (int256) {
    Position memory position = s_positions[user];
    if (_token != position.token) revert Perpetual__TokenMismatch();
    if (!position.isOpen) revert Perpetual__PositionNotOpen();

    int256 currentPrice = int256(getUsdValue(_size, _token));
    int256 entryPrice = int256(position.entryPrice);
    
    return position.isLong ? (currentPrice - entryPrice) : (entryPrice - currentPrice);
}
 function closePosition() public nonReentrant {
    Position memory position = s_positions[msg.sender];
    if (!position.isOpen) revert Perpetual__PositionNotOpen();
    
    int256 pnl = calculatePnl(position.size, position.token, msg.sender);
    uint256 collateralAmount = position.collateral;
    delete s_positions[msg.sender];

    if (pnl > 0) {
         
         uint256 profitInTokens = getTokenAmount(uint256(pnl),position.token);
         s_totalLiquidity -= uint256(profitInTokens);
        IERC20(position.token).safeTransfer(msg.sender, collateralAmount + profitInTokens);
        emit PositionClosed(msg.sender, position.size, position.isLong, position.token, collateralAmount);
    } 
    else if (pnl < 0) {
        uint256 lossInUsd = uint256(-pnl);
        uint256 collateralAmountInUsd = getCollateralAmountInUsd(collateralAmount, position.token);
        
        if (collateralAmountInUsd > lossInUsd) {
            uint256 remainingCollateralInUsd = collateralAmountInUsd - lossInUsd;
            s_totalLiquidity += lossInUsd;
            uint256 remainingCollateralInTokens = getTokenAmount(remainingCollateralInUsd,position.token);
            IERC20(position.token).safeTransfer(msg.sender, remainingCollateralInTokens);
            emit PositionClosed(msg.sender, position.size, position.isLong, position.token, remainingCollateralInUsd);
        } else {
            s_totalLiquidity += collateralAmountInUsd;
            emit PositionClosed(msg.sender, position.size, position.isLong, position.token, 0);
            // No transfer needed as user lost all collateral
        }
    } else {
        // PnL is 0 no loss
        IERC20(position.token).safeTransfer(msg.sender, collateralAmount);
        emit PositionClosed(msg.sender, position.size, position.isLong, position.token, collateralAmount);
    }

}
function decreasePositionSize(uint256 _size) public  moreThanZero(_size){
    Position storage position = s_positions[msg.sender];
    if(!s_positions[msg.sender].isOpen) revert Perpetual__PositionNotOpen();
    if(_size > position.size) revert Perpetual__DecreasePositionInvalid();
    
    
    int256 pnlToBeReduced = calculateProportionalPnlForDecreaseSize(position, _size);
    uint256 newCollateralInUsd = calculateNewCollateral(position, pnlToBeReduced);
    updatePositionAfterDecrease(position, _size, newCollateralInUsd);
    handleLiquidityAdjustments(uint256(pnlToBeReduced),position.token);
}
function calculateNewCollateral(Position memory position, int256 pnlToBeReduced) public view returns (uint256) {
    uint256 collateralInUsd = getCollateralAmountInUsd(position.collateral, position.token);
    int256 adjustedCollateral = int256(collateralInUsd) + pnlToBeReduced;

    if (adjustedCollateral < 0) revert Perpetual__DecreasePositionInvalid();
    return uint256(adjustedCollateral);
}
function calculateProportionalPnlForDecreaseSize(Position memory position, uint256 _reduceSize) public view returns (int256) {
    int256 currentPrice = int256(getUsdValue(position.size, position.token));
    int256 entryPrice = int256(position.entryPrice);
    int256 totalPnl = position.isLong
        ? int256(position.size) * (currentPrice - entryPrice)
        : int256(position.size) * (entryPrice - currentPrice);

    return (totalPnl * int256(_reduceSize)) / int256(position.size);
}
function updatePositionAfterDecrease(
    Position memory position,
    uint256 _reduceSize,
    uint256 newCollateralInUsd
) public {
    position.size -= _reduceSize;

    // Update collateral
    position.collateral = getTokenAmount(newCollateralInUsd, position.token);

    // Update entry price proportionally
    position.entryPrice = getUsdValue(position.size, position.token);

    // Close position if fully reduced
    if (position.size == 0) closePosition();
}

function handleLiquidityAdjustments(uint256 pnlInTokensToBeReduced, address token) internal {
    Position storage position = s_positions[msg.sender];
    uint256 userTokenBalance = getTokenAmount(position.size,token);
    if (userTokenBalance > pnlInTokensToBeReduced) {
        uint256 lossInToken = userTokenBalance - pnlInTokensToBeReduced;
        s_totalLiquidity += lossInToken;
    } 
    else if (userTokenBalance < pnlInTokensToBeReduced) {
        // Profit Scenario
        uint256 profitInTokens = pnlInTokensToBeReduced - userTokenBalance;

        if (s_totalLiquidity < profitInTokens) {
            revert Perpetual__NotEnoughLiquidity();
        }

        s_totalLiquidity -= profitInTokens; // Decrease liquidity pool
    }
}

 
function getCollateralAmountInUsd(uint256 _amount,address _token) public view returns(uint256){
  uint256 usdValue = getUsdValue(_amount,_token);
  return usdValue;
}
function getUsdValue(uint256 _amount,address _token) public view returns(uint256){
    AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_token]);
    (,int256 price,,,) = priceFeed.latestRoundData();
    return (uint256(price) * ADDITIONAL_FEED_PRECISION) * _amount / PRECISION;

}
function getTokenAmount(uint256 _usdAmount, address _token) public view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_token]);
        (,int256 price,,,) = priceFeed.latestRoundData();
        // Convert USD amount to token amount
        return (_usdAmount * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }
 

}
# Nayashi Perps

Nayashi Perps is a decentralized perpetual trading protocol that enables users to open, manage, and liquidate leveraged positions on BTC without converting collateral to USD. This protocol is designed with safety mechanisms like liquidity utilization limits and an auto-deleveraging (ADL) system inspired by GMX.

## Features

- **Liquidity Management**:
  - Liquidity Providers can deposit and withdraw funds.
  - Configurable liquidity utilization percentages.
  - Restricted liquidity withdrawals for reserved positions.

- **Trading**:
  - Open and manage perpetual positions with adjustable size and collateral.
  - Real-time price fetching for accurate trading execution.

- **Risk Management**:
  - Positions are liquidated when leverage equals the  leverage threshold.
  - Auto-deleveraging (ADL) to ensure system stability.

- **Unique Position Logic**:
  - Entry prices are based on `size` rather than collateral.
  - No share allocation to Liquidity Providers.
  - Collateral amounts are not normalized to USD.

## Technology Stack

- **Programming Language**: Solidity
- **Testing Framework**: Foundry
- **Static Analysis**: Slither
- **Development Tools**: 
  - `forge` for testing and simulations.
  - Price feed integrations (e.g., Chainlink Oracles).

## Contract Functions

### Core Functions

1. **Liquidity Management**:
    - `depositLiquidity()`: Adds funds to the liquidity pool.
    - `withdrawLiquidity()`: Removes funds from the pool, if available.

2. **Trading**:
    - `openPosition(uint256 size, uint256 collateral)`: Opens a new position.
    - `adjustPosition(uint256 newSize, uint256 newCollateral)`: Adjusts an existing position.



## Installation

1. Clone the repository:

   ```bash
   git clone https://github.com/your-username/nayashi-perps.git
   cd nayashi-perps

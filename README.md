
# 🪙 SMC Gold Scalper EA (MetaTrader 5)

An automated MetaTrader 5 (MT5) Expert Advisor (EA) designed specifically for **XAUUSD (Gold) CFD trading** utilizing **Smart Money Concepts (SMC)**, **Fair Value Gaps (FVG)**, and **Order Blocks (OB)**. 

This EA scans the markets for institutional order flow, identifies imbalances, detects structural shifts, and executes high-probability setups with strict risk management parameters tailored for prop firm evaluations and live retail trading.

---

## 🚀 Core Features

*   **Market Structure Shifts (MSS / BOS):** Detects changes in market character (CHoCH) and Break of Structure (BOS) on lower timeframes (e.g., 5-Minute) aligned with higher timeframe trends.
*   **Order Block Detection:** Automatically maps bullish and bearish institutional order blocks (supply/demand zones) with dynamic volume validation.
*   **Fair Value Gap (FVG) Confluence:** Identifies price imbalances and acts on setups where price retraces into an FVG that coincides with a valid Order Block.
*   **Precision Execution Engine:** Enters trades at the mitigation of the zone with tight, optimized stop-losses including customizable point buffers.
*   **Prop-Firm Friendly Risk Management:** Features strict risk-per-trade limits, fixed dollar or percentage allocations, and automated break-even/trailing stop scripts to eliminate trailing drawdown traps.

---

## 🛠 Architecture & Technical Overview

The codebase is split logically between localized MQL5 scripts for chart execution and high-performance automated testing scripts.

├── Experts/
│   └── SMC_Gold_Scalper_EA.mq5    # Main EA Execution Code (MQL5)
|
├── Include/
│   ├── SMC_Structures.mqh         # Structural definitions (BOS, CHoCH)
│   └── Imbalance_Finder.mqh       # FVG & Order Block detection logic
├── Scripts/
│   └── Set_BreakEven.mq5          # Flat Break-Even recovery tool
└── Tests/
└── mt5_backtest_auto.py       # Python script for local multi-variable optimization


### ⚡ Technical Strategies Leveraged
1. **The Squeeze & Imbalance:** Monitors volatility contraction using Bollinger Bands/Keltner Channels alongside the `LazyBear Squeeze Momentum` logic to filter out choppy markets.
2. **Mitigation Entry:** Wait for price to leave a zone, create an FVG, and execute the limit/market order right as the market returns to mitigate the structural imbalance.

---

## ⚙️ Input Parameters & Configuration

| Parameter Category | Input Variable | Default Value | Description |
| :--- | :--- | :--- | :--- |
| **Risk Management** | `Risk_Percent_Per_Trade` | `1.0` | Percentage of equity risked per setup |
| | `Use_Fixed_Lot_Size` | `false` | Toggle to use static lots instead of dynamic |
| | `Fixed_Lot_Size` | `0.10` | Static volume used if above is true |
| **SMC Settings** | `HTF_Trend_Filter` | `true` | Aligns entries with the 200 EMA direction |
| | `Min_OB_Volume` | `150` | Minimum tick volume required to validate an OB |
| | `FVG_Buffer_Points` | `10` | Point offset buffer added outside the FVG zone |
| **Trade Management**| `StopLoss_Buffer` | `10` | 1-point (10 points) buffer added to structural SL |
| | `Auto_BreakEven_R_Multiple`| `2.0` | Moves SL to entry once trade hits 2R profit |
| | `Use_Trailing_Stop` | `false` | Enable native MT5 trailing stop logic |

---

## 📊 Automated Backtesting (Python Integration)

The project includes a robust **Python-based automation harness** located in the `/Tests` folder. This allows you to bypass the manual MT5 Strategy Tester UI and programmatically iterate through over 40+ input parameters across years of historical MQL5 data.

### Prerequisites
* MetaTrader 5 Terminal installed (`MT5 - Demo 3` configuration supported)
* Python 3.8+ with `MetaTrader5`, `pandas`, and `numpy` packages.

### Running Multi-Variable Optimization
```bash
python Tests/mt5_backtest_auto.py --config optimal_gold_set.json --start-year 2024
```
This script initializes the MT5 terminal via the CLI, pushes optimization sets, parses the generated CSV spreadsheet logs, and profiles losing trade patterns to dynamically adjust target time-of-day reversal zones.

---

## 📥 Installation

1. Open your MetaTrader 5 Terminal.
2. Navigate to `File` -> `Open Data Folder`.
3. Copy the contents of the `Experts/`, `Include/`, and `Scripts/` folders into their respective directories inside `MQL5/`.
4. Right-click **Expert Advisors** in the Navigator panel and select **Refresh**.
5. Drag `SMC_Gold_Scalper_EA` onto a **XAUUSD 5-Minute** chart.
6. Ensure **Algo Trading** is enabled in the MT5 top ribbon.

---

## ⚠️ Disclaimer

Trading foreign exchange, CFDs, and commodities like Gold on margin carries a high level of risk and may not be suitable for all investors. The authors of this project assume zero liability for financial losses incurred through the deployment of this Expert Advisor. Always thoroughly backtest and forward-test on a demo account before risking live or funded capital.


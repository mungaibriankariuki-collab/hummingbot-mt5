# Hummingbot MT5

Hummingbot's trading strategies, rewritten as MetaTrader 5 Expert Advisors.

[Hummingbot](https://github.com/hummingbot/hummingbot) is a Python bot for crypto exchanges. This repo ports its
strategy logic (controllers and executors from `strategy_v2`, plus the Avellaneda market maker) to MQL5, so it
runs inside MT5 on any broker's forex, metals, indices or CFD symbols.

## The EAs

| EA | Hummingbot source | What it does |
|---|---|---|
| `HB_PMM_Simple` | `controllers/market_making/pmm_simple` | Limit orders at fixed spreads around the mid price |
| `HB_PMM_Dynamic` | `controllers/market_making/pmm_dynamic` | MACD shifts the reference price, NATR sets the spreads |
| `HB_DMan_Maker_V2` | `controllers/market_making/dman_maker_v2` | Market making where every level is a DCA ladder |
| `HB_Avellaneda` | `strategy/avellaneda_market_making` | Avellaneda-Stoikov: quotes lean against inventory, widen with volatility |
| `HB_Bollinger` | `controllers/directional_trading/bollinger_v1` (and `v2`) | Mean reversion on Bollinger %B |
| `HB_MACD_BB` | `controllers/directional_trading/macd_bb_v1` | Bollinger %B confirmed by MACD |
| `HB_SuperTrend` | `controllers/directional_trading/supertrend_v1` | Trend following with SuperTrend |
| `HB_DMan_V3` | `controllers/directional_trading/dman_v3` | Bollinger signal executed as a DCA ladder |
| `HB_BollinGrid` | `controllers/directional_trading/bollingrid` | Bollinger signal launches a grid sized by the bandwidth |
| `HB_Grid_Strike` | `controllers/generic/grid_strike` | One-sided grid between a start and end price |
| `HB_Multi_Grid_Strike` | `controllers/generic/multi_grid_strike` | Up to three grids on one symbol |
| `HB_Stat_Arb` | `controllers/generic/stat_arb` | Pairs trading on the z-score of two correlated symbols |

All of them run on the same engine in `MQL5/Include/Hummingbot`:

- **PositionExecutor**: one entry with Hummingbot's triple barrier (stop loss, take profit, time limit, trailing stop).
- **DCAExecutor**: a ladder of limit orders managed against the average entry price.
- **GridExecutor**: evenly spaced levels between a start and end price, each with its own take profit. The grid has a
  limit (stop-out) price, and it can also have a stop loss, time limit and trailing stop.
- **Controllers**: the directional and market-making controller bases, with max executors per side, cooldowns,
  level refreshes and stop-loss cooldowns.

Default inputs match Hummingbot's defaults.

## Install

1. Download `hummingbot-mt5.zip` from [Releases](../../releases), or the `hummingbot-mt5` artifact of the latest
   [Actions](../../actions) run.
2. In MT5 open **File → Open Data Folder** and copy the zip's `MQL5` folder into it, merging folders.
3. Restart MT5, or right-click **Expert Advisors → Refresh** in the Navigator.
4. Drag an EA onto a chart, check **Allow Algo Trading**, and set the inputs.

The `.ex5` files run as they are. To build from source, open any `.mq5` in MetaEditor and press **Compile**.

**Requirements:** a **hedging** account, which most brokers offer. Hummingbot runs one position per executor, and a
netting account would merge those positions. `HB_Avellaneda` also runs on netting accounts.

Use a different magic number for each chart running the same EA.

## How Hummingbot settings map to MT5

| Hummingbot | MT5 input |
|---|---|
| `connector_name`, `trading_pair` | the chart's symbol (Stat Arb: the dominant and hedge symbol inputs) |
| `total_amount_quote` | `Total lots`, split the way Hummingbot splits the quote amount. Stat Arb uses account-currency notional. |
| `interval` (e.g. `3m`) | `Candle interval` (M3) |
| `stop_loss`, `take_profit`, spreads | the same fractions: `0.02` means 2% |
| `time_limit`, `cooldown_time`, refresh times | seconds |
| `trailing_stop: 0.015,0.005` | `Trailing stop activation` = 0.015, `Trailing stop delta` = 0.005 |
| `leverage`, `position_mode` | set by your broker account |

## How it differs from Hummingbot

- **Server-side protection.** Stop loss and take profit are attached to every position as MT5 SL/TP, so they still
  work if the terminal goes offline. The trailing stop moves the SL. The EA also checks every barrier itself once per
  second, the same clock Hummingbot uses.
- **Restarts are safe.** Executors are saved to `MQL5/Files/Hummingbot/` and restored when the EA restarts, for
  example after a timeframe change, a terminal restart or an input change. Running executors keep the settings they
  started with, as in Hummingbot.
- **Removing the EA** cancels its pending orders (`Cancel pending orders when the EA is removed`). Open positions
  stay on the account with their SL/TP.
- **Limit orders.** A `LIMIT` order that would cross the spread is sent as a market order, which is what would happen
  on an exchange. A `LIMIT_MAKER` order is moved back behind the bid/ask. Prices also respect the broker's
  stops level.
- **Avellaneda.** MT5 symbols have no public trade feed, so `kappa` (order book liquidity) is an input. Leave it at 0
  and the EA picks the kappa at which the model's liquidity spread equals the average bid/ask spread. Inventory is
  the EA's net position measured against `Inventory size in lots`, in place of base and quote wallet balances.
  Opposite fills are netted with Close By.
- **Fees.** PnL percentages exclude commissions. The realized PnL shown on the chart includes commission and swap.
- **Grid sizing.** The number of grid levels follows Hummingbot's formula, with the broker's minimum lot in place of
  the exchange's minimum notional.

## Not ported

These Hummingbot strategies depend on crypto infrastructure that MT5 doesn't have:

- cross-exchange market making, AMM arbitrage, XEMM and the arbitrage controller (they need two venues)
- the liquidity-mining and LP-rebalancer strategies (they need DEX liquidity pools)
- `hedge_asset` (spot wallet hedged with perpetuals)
- `quantum_grid_allocator` (a multi-asset crypto portfolio)
- `ai_livestream` (an external signal feed)
- `pmm_v1` and `pmm_mister`, which are variants of PMM Simple

## Risk

These EAs trade real money. Market making and grids lose money in strong trends. The Hummingbot defaults (2–3%
stops, 1–2% spreads) were made for volatile crypto pairs and are wide for most forex symbols. Run every EA in the
Strategy Tester and on a demo account before going live.

## License

Apache-2.0, like Hummingbot. See `LICENSE` and `NOTICE`.

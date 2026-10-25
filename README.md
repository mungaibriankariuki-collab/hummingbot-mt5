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

Default inputs match Hummingbot's defaults except for stop losses (see risk to reward), and auto-tune fits them to whatever symbol the EA runs on.

## Risk to reward (1:2 or better)

`Min reward:risk` (default 2) makes every take profit at least twice the stop loss. If you enter a smaller take
profit, it is raised to 2 x the stop loss. A trailing stop never locks in less than that either: its activation is
raised so that activation minus delta is at least 2 x the stop loss. Set it to 0 to use Hummingbot's own targets.

The defaults were changed to match: stop loss 1% and take profit 2% (Hummingbot uses 3% and 2%). DMan V3 gets a 2%
take profit and a 2.5% / 0.5% trailing stop, and Stat Arb closes the pair at -0.5% / +1%. Auto-tune scales stop
and target by the same factor, so the ratio holds on every symbol.

Exits that are not the take profit can still be smaller than 2R: the time limit (45 minutes by default) and a
market-making order refresh close at the market price. Grids have no per-trade stop (each level has a take profit,
and the whole grid has a stop-out price), and Avellaneda has no stop loss or take profit, so the rule doesn't apply
to them.

## Auto-tune for every symbol

Hummingbot's defaults (1–3% targets, 1–2% spreads) were written for crypto pairs that move about 5% a day. On a
forex pair that moves 0.6% a day they would almost never trigger. Every EA therefore measures its symbol when it
starts and scales the percentage settings to it, so the same defaults work on any forex pair, metal, index, crypto
CFD or synthetic index without a per-symbol preset.

1. It measures the symbol's average daily range: the 14-day ATR as a fraction of price. If daily history isn't
   available it uses H4, H1 or M15 bars and scales them to a day.
2. Factor = daily range ÷ `Daily range the settings are written for` (default 0.05, Hummingbot's crypto). The factor
   is kept between 0.02 and 3.
3. Stop losses, take profits, trailing stops, market-making spreads, DCA spreads, grid spacing, auto grid ranges,
   activation bounds and the SuperTrend distance are multiplied by the factor.
4. Take profits, stops, quotes and grid spacing are kept at least `Keep ... this many spreads away` (default 3)
   bid/ask spreads from the price, so a trade can't close inside the spread.

The factor and the measurements appear on the chart and in the Experts log, e.g.
`auto-tune x0.118 | EURUSD daily range 0.590% (D1), spread 0.0010% | min target 0.0030%`.

Rough effect on `HB_PMM_Simple` (stop loss / take profit / first spread) with typical daily ranges:

| Symbol | Daily range | Factor | Stop loss | Take profit | Spread |
|---|---|---|---|---|---|
| Defaults as entered | 5% | 1.00 | 1% | 2% | 1% |
| BTCUSD | ~3% | ~0.60 | 0.6% | 1.2% | 0.6% |
| XAUUSD | ~1.5% | ~0.30 | 0.3% | 0.6% | 0.3% |
| NAS100 | ~1.3% | ~0.26 | 0.26% | 0.52% | 0.26% |
| EURUSD | ~0.6% | ~0.12 | 0.12% | 0.24% | 0.12% |

The real numbers come from your broker's prices at start-up. What is not scaled: lot sizes, time limits, cooldowns,
indicator lengths and thresholds (%B, z-score), and settings that already follow volatility (PMM Dynamic's NATR
spreads, DMan V3's dynamic spreads and targets, BollinGrid's Bollinger-width grid, Avellaneda's model). Manual grid
prices in Multi Grid Strike are used as entered.

Inputs you type are read in the same crypto terms and scaled too. To use exact values, set
`Scale % settings to this symbol's volatility` to false. Executors that are already running keep the settings they
started with.

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

These EAs trade real money. Market making and grids lose money in strong trends. Auto-tune sizes the distances to
each symbol, but it doesn't make a strategy profitable on it, and `Total lots` is not scaled: 0.1 lots of an index
or gold carries far more risk than 0.1 lots of EURUSD. Run every EA in the Strategy Tester and on a demo account
before going live.

## License

Apache-2.0, like Hummingbot. See `LICENSE` and `NOTICE`.

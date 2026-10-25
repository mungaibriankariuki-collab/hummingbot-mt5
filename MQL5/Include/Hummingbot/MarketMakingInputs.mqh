//+------------------------------------------------------------------+
//| Hummingbot MT5 - MarketMakingControllerBase inputs               |
//+------------------------------------------------------------------+
#ifndef HB_MARKET_MAKING_INPUTS_MQH
#define HB_MARKET_MAKING_INPUTS_MQH

#ifndef HB_DEF_BUY_SPREADS
#define HB_DEF_BUY_SPREADS "0.01,0.02"
#endif
#ifndef HB_DEF_SELL_SPREADS
#define HB_DEF_SELL_SPREADS "0.01,0.02"
#endif

input group "Order levels"
input double             InpTotalLots           = 0.1;  // Total lots (total_amount_quote), split over all levels
input string             InpBuySpreads          = HB_DEF_BUY_SPREADS;  // Buy spreads, comma separated
input string             InpSellSpreads         = HB_DEF_SELL_SPREADS; // Sell spreads, comma separated
input string             InpBuyAmountsPct       = "";   // Buy amount weights (empty = equal)
input string             InpSellAmountsPct      = "";   // Sell amount weights (empty = equal)
input int                InpExecutorRefreshTime = 300;  // Refresh unfilled orders after (seconds)
input int                InpCooldownTime        = 15;   // Level cooldown after a stop loss (seconds)
input group "Triple barrier (fractions: 0.02 = 2%)"
input double             InpStopLoss            = 0.01; // Stop loss (0 = off)
input double             InpTakeProfit          = 0.02; // Take profit (0 = off)
input int                InpTimeLimit           = 2700; // Time limit in seconds (0 = off)
input ENUM_HB_ORDER_TYPE InpTakeProfitOrderType = HB_ORDER_LIMIT; // Take profit order type
input double             InpTrailingActivation  = 0.0;  // Trailing stop activation (0 = off)
input double             InpTrailingDelta       = 0.0;  // Trailing stop delta

#endif

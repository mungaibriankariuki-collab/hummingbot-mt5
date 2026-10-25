//+------------------------------------------------------------------+
//| Hummingbot MT5 - DirectionalTradingControllerBase inputs         |
//+------------------------------------------------------------------+
#ifndef HB_DIRECTIONAL_INPUTS_MQH
#define HB_DIRECTIONAL_INPUTS_MQH

#ifndef HB_DEF_TRAILING_ACTIVATION
#define HB_DEF_TRAILING_ACTIVATION 0.0
#endif
#ifndef HB_DEF_TRAILING_DELTA
#define HB_DEF_TRAILING_DELTA 0.0
#endif

input group "Executors"
input double             InpTotalLots           = 0.1;  // Total lots (total_amount_quote), split by max executors per side
input int                InpMaxExecutorsPerSide = 2;    // Max executors per side
input int                InpCooldownTime        = 300;  // Cooldown between executors on one side (seconds)
input group "Triple barrier (fractions: 0.02 = 2%)"
input double             InpStopLoss            = 0.01; // Stop loss (0 = off)
input double             InpTakeProfit          = 0.02; // Take profit (0 = off)
input int                InpTimeLimit           = 2700; // Time limit in seconds (0 = off)
input ENUM_HB_ORDER_TYPE InpTakeProfitOrderType = HB_ORDER_LIMIT; // Take profit order type
input double             InpTrailingActivation  = HB_DEF_TRAILING_ACTIVATION; // Trailing stop activation (0 = off)
input double             InpTrailingDelta       = HB_DEF_TRAILING_DELTA;      // Trailing stop delta

#endif

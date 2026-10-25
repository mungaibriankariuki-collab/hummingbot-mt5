//+------------------------------------------------------------------+
//| Hummingbot MT5 - GridStrike / MultiGridStrike shared inputs      |
//+------------------------------------------------------------------+
#ifndef HB_GRID_INPUTS_MQH
#define HB_GRID_INPUTS_MQH

input group "Grid execution"
input double             InpTotalLots           = 0.1;   // Total lots (total_amount_quote)
input double             InpMinSpreadBetweenOrders = 0.001; // Min spread between levels (0.001 = 0.1%)
input double             InpMinOrderLots        = 0.0;   // Min lots per level (0 = broker minimum)
input int                InpMaxOpenOrders       = 2;     // Max resting entry orders
input int                InpMaxOrdersPerBatch   = 1;     // Orders placed per batch
input int                InpOrderFrequency      = 3;     // Seconds between batches
input double             InpActivationBounds    = 0.0;   // Only keep orders within this distance of mid (0 = off)
input bool               InpKeepPosition        = false; // Keep the position when the limit price is hit
input group "Grid risk (fractions: 0.001 = 0.1%)"
input double             InpTakeProfit          = 0.001; // Take profit per level
input double             InpStopLoss            = 0.0;   // Stop loss on the whole grid position (0 = off)
input int                InpTimeLimit           = 0;     // Time limit in seconds (0 = off)
input double             InpTrailingActivation  = 0.0;   // Trailing stop activation (0 = off)
input double             InpTrailingDelta       = 0.0;   // Trailing stop delta
input ENUM_HB_ORDER_TYPE InpOpenOrderType       = HB_ORDER_LIMIT_MAKER; // Level entry order type
input ENUM_HB_ORDER_TYPE InpTakeProfitOrderType = HB_ORDER_LIMIT_MAKER; // Level take profit order type

void HbGridBarrier(HbTripleBarrier &tb)
  {
   tb.Init();
   tb.take_profit = HbTuneDist(InpTakeProfit);
   tb.stop_loss = HbTuneDist(InpStopLoss);
   tb.time_limit = InpTimeLimit;
   tb.trailing_activation = HbTuneDist(InpTrailingActivation);
   tb.trailing_delta = HbTuneDist(InpTrailingDelta);
   tb.open_order_type = InpOpenOrderType;
   tb.take_profit_order_type = InpTakeProfitOrderType;
  }

#endif

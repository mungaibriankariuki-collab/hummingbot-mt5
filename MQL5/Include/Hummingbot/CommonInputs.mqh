//+------------------------------------------------------------------+
//| Hummingbot MT5 - inputs shared by every EA                       |
//| Define HB_DEFAULT_MAGIC before including this file.              |
//+------------------------------------------------------------------+
#ifndef HB_COMMON_INPUTS_MQH
#define HB_COMMON_INPUTS_MQH

input group "General"
input long   InpMagic          = HB_DEFAULT_MAGIC; // Magic number (unique per chart)
input int    InpDeviation      = 10;               // Max slippage for market orders (points)
input bool   InpCancelOnRemove = true;             // Cancel pending orders when the EA is removed
input bool   InpVerbose        = true;             // Log executor activity to the Experts tab
input group "Symbol auto-tune"
input bool   InpAutoTune       = true;             // Scale % settings to this symbol's volatility
input double InpTuneRefRange   = 0.05;             // Daily range the settings are written for (0.05 = 5%, Hummingbot crypto)
input double InpTuneMinSpreads = 3.0;              // Keep take profits, stops and quotes at least this many spreads away

#include "AutoTune.mqh"

void HbAutoTune(const string sym, const string sym2 = "")
  {
   HbAutoTuneInit(InpAutoTune, InpTuneRefRange, InpTuneMinSpreads, sym, sym2);
  }

#endif

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

#endif

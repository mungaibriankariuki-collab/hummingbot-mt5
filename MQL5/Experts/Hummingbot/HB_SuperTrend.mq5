//+------------------------------------------------------------------+
//| HB_SuperTrend.mq5                                                |
//| Hummingbot controllers/directional_trading/supertrend_v1         |
//+------------------------------------------------------------------+
#property copyright   "Hummingbot strategies ported to MQL5 - Apache-2.0"
#property version     "1.00"
#property description "SuperTrend trend following (Hummingbot supertrend_v1)."
#property description "Trades in the SuperTrend direction while price is within the percentage threshold of the line."

#define HB_DEFAULT_MAGIC 710103
#include <Hummingbot\CommonInputs.mqh>
#include <Hummingbot\Controllers.mqh>
#include <Hummingbot\DirectionalInputs.mqh>

input group "SuperTrend"
input ENUM_TIMEFRAMES InpInterval            = PERIOD_M3; // Candle interval
input int             InpLength              = 20;        // SuperTrend ATR length
input double          InpMultiplier          = 4.0;       // SuperTrend ATR multiplier
input double          InpPercentageThreshold = 0.01;      // Max distance from the line (0.01 = 1%)

class CSuperTrendController : public CHbDirectionalController
  {
protected:
   virtual void      UpdateProcessedData(void)
     {
      m_signal = 0;
      double open[], high[], low[], close[];
      if(!HbGetCandles(m_symbol, InpInterval, InpLength + 10, open, high, low, close))
        {
         m_signal_info = "| waiting for candles";
         return;
        }
      double trend[], dir[];
      HbSuperTrend(high, low, close, InpLength, InpMultiplier, trend, dir);
      int last = ArraySize(close) - 1;
      if(!HbValid(trend[last]) || close[last] == 0)
         return;
      double distance = MathAbs(close[last] - trend[last]) / close[last];
      double threshold = HbTune(InpPercentageThreshold);
      if(dir[last] == 1 && distance < threshold)
         m_signal = 1;
      else
         if(dir[last] == -1 && distance < threshold)
            m_signal = -1;
      m_signal_info = StringFormat("| direction %d distance %.3f%%", (int)dir[last], distance * 100.0);
     }
  };

CSuperTrendController g_ctrl;

int OnInit()
  {
   g_hb_verbose = InpVerbose;
   HbInit("SuperTrend", InpMagic, InpDeviation);
   if(!HbCheckAccount())
      return INIT_FAILED;
   if(InpLength < 2 || InpMultiplier <= 0 || InpTotalLots <= 0)
      return INIT_PARAMETERS_INCORRECT;
   g_ctrl.SetIdentity("supertrend_v1", _Symbol);
   HbAutoTune(_Symbol);
   g_ctrl.ConfigureDirectional(InpTotalLots, InpMaxExecutorsPerSide, InpCooldownTime, HbTuneDist(InpStopLoss),
                               HbTuneDist(InpTakeProfit), InpTimeLimit, InpTakeProfitOrderType,
                               HbTuneDist(InpTrailingActivation), HbTuneDist(InpTrailingDelta));
   g_ctrl.Load();
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason) { HbFinishController(&g_ctrl, reason, InpCancelOnRemove); }
void OnTick()  { g_ctrl.Run(); }
void OnTimer() { g_ctrl.Run(); }

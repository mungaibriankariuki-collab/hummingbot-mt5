//+------------------------------------------------------------------+
//| HB_Bollinger.mq5                                                 |
//| Hummingbot controllers/directional_trading/bollinger_v1 (and v2, |
//| which produces the same signal)                                  |
//+------------------------------------------------------------------+
#property copyright   "Hummingbot strategies ported to MQL5 - Apache-2.0"
#property version     "1.00"
#property description "Bollinger Bands mean reversion (Hummingbot bollinger_v1/v2)."
#property description "Long when %B < long threshold, short when %B > short threshold."
#property description "Each signal opens a market position executor with stop loss, take profit, time limit and trailing stop."

#define HB_DEFAULT_MAGIC 710101
#include <Hummingbot\CommonInputs.mqh>
#include <Hummingbot\Controllers.mqh>
#include <Hummingbot\DirectionalInputs.mqh>

input group "Bollinger Bands"
input ENUM_TIMEFRAMES InpInterval         = PERIOD_M3; // Candle interval
input int             InpBBLength         = 100;       // Bollinger length
input double          InpBBStd            = 2.0;       // Bollinger standard deviations
input double          InpBBLongThreshold  = 0.0;       // Long when %B is below
input double          InpBBShortThreshold = 1.0;       // Short when %B is above

class CBollingerController : public CHbDirectionalController
  {
protected:
   virtual void      UpdateProcessedData(void)
     {
      m_signal = 0;
      double close[];
      if(!HbGetCloses(m_symbol, InpInterval, InpBBLength, close))
        {
         m_signal_info = "| waiting for candles";
         return;
        }
      double lower[], middle[], upper[], bbp[], bbb[];
      HbBBands(close, InpBBLength, InpBBStd, lower, middle, upper, bbp, bbb);
      double p = bbp[ArraySize(bbp) - 1];
      if(!HbValid(p))
         return;
      if(p < InpBBLongThreshold)
         m_signal = 1;
      else
         if(p > InpBBShortThreshold)
            m_signal = -1;
      m_signal_info = StringFormat("| %%B %.3f", p);
     }
  };

CBollingerController g_ctrl;

int OnInit()
  {
   g_hb_verbose = InpVerbose;
   HbInit("Bollinger", InpMagic, InpDeviation);
   if(!HbCheckAccount())
      return INIT_FAILED;
   if(InpBBLength < 2 || InpTotalLots <= 0)
      return INIT_PARAMETERS_INCORRECT;
   g_ctrl.SetIdentity("bollinger", _Symbol);
   g_ctrl.ConfigureDirectional(InpTotalLots, InpMaxExecutorsPerSide, InpCooldownTime, InpStopLoss, InpTakeProfit,
                               InpTimeLimit, InpTakeProfitOrderType, InpTrailingActivation, InpTrailingDelta);
   g_ctrl.Load();
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason) { HbFinishController(&g_ctrl, reason, InpCancelOnRemove); }
void OnTick()  { g_ctrl.Run(); }
void OnTimer() { g_ctrl.Run(); }

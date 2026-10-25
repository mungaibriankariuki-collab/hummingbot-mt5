//+------------------------------------------------------------------+
//| HB_MACD_BB.mq5                                                   |
//| Hummingbot controllers/directional_trading/macd_bb_v1            |
//+------------------------------------------------------------------+
#property copyright   "Hummingbot strategies ported to MQL5 - Apache-2.0"
#property version     "1.00"
#property description "Bollinger %B filtered by MACD (Hummingbot macd_bb_v1)."
#property description "Long: %B < long threshold, MACD histogram > 0 and MACD < 0. Short: the mirror image."

#define HB_DEFAULT_MAGIC 710102
#include <Hummingbot\CommonInputs.mqh>
#include <Hummingbot\Controllers.mqh>
#include <Hummingbot\DirectionalInputs.mqh>

input group "Bollinger Bands"
input ENUM_TIMEFRAMES InpInterval         = PERIOD_M3; // Candle interval
input int             InpBBLength         = 100;       // Bollinger length
input double          InpBBStd            = 2.0;       // Bollinger standard deviations
input double          InpBBLongThreshold  = 0.0;       // Long when %B is below
input double          InpBBShortThreshold = 1.0;       // Short when %B is above
input group "MACD"
input int             InpMACDFast         = 21;        // MACD fast period
input int             InpMACDSlow         = 42;        // MACD slow period
input int             InpMACDSignal       = 9;         // MACD signal period

class CMacdBBController : public CHbDirectionalController
  {
protected:
   virtual void      UpdateProcessedData(void)
     {
      m_signal = 0;
      int records = (int)MathMax(MathMax(InpMACDSlow, InpMACDFast), MathMax(InpMACDSignal, InpBBLength)) + 20;
      double close[];
      if(!HbGetCloses(m_symbol, InpInterval, records, close))
        {
         m_signal_info = "| waiting for candles";
         return;
        }
      double lower[], middle[], upper[], bbp[], bbb[];
      HbBBands(close, InpBBLength, InpBBStd, lower, middle, upper, bbp, bbb);
      double macd[], macds[], macdh[];
      HbMACD(close, InpMACDFast, InpMACDSlow, InpMACDSignal, macd, macds, macdh);
      int last = ArraySize(close) - 1;
      if(!HbValid(bbp[last]) || !HbValid(macdh[last]))
         return;
      if(bbp[last] < InpBBLongThreshold && macdh[last] > 0 && macd[last] < 0)
         m_signal = 1;
      else
         if(bbp[last] > InpBBShortThreshold && macdh[last] < 0 && macd[last] > 0)
            m_signal = -1;
      m_signal_info = StringFormat("| %%B %.3f MACD %.6f hist %.6f", bbp[last], macd[last], macdh[last]);
     }
  };

CMacdBBController g_ctrl;

int OnInit()
  {
   g_hb_verbose = InpVerbose;
   HbInit("MACD-BB", InpMagic, InpDeviation);
   if(!HbCheckAccount())
      return INIT_FAILED;
   if(InpBBLength < 2 || InpMACDFast < 1 || InpMACDSlow <= InpMACDFast || InpMACDSignal < 1 || InpTotalLots <= 0)
      return INIT_PARAMETERS_INCORRECT;
   g_ctrl.SetIdentity("macd_bb_v1", _Symbol);
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

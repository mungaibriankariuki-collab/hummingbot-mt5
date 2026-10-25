//+------------------------------------------------------------------+
//| HB_DMan_V3.mq5                                                   |
//| Hummingbot controllers/directional_trading/dman_v3               |
//+------------------------------------------------------------------+
#property copyright   "Hummingbot strategies ported to MQL5 - Apache-2.0"
#property version     "1.00"
#property description "D-Man V3 (Hummingbot dman_v3): Bollinger mean reversion executed as a DCA ladder."
#property description "Optionally scales the ladder spreads and the stops by the Bollinger bandwidth."

#define HB_DEFAULT_MAGIC 710104
#define HB_DEF_TRAILING_ACTIVATION 0.015
#define HB_DEF_TRAILING_DELTA 0.005
#include <Hummingbot\CommonInputs.mqh>
#include <Hummingbot\Controllers.mqh>
#include <Hummingbot\DirectionalInputs.mqh>

input group "Bollinger Bands"
input ENUM_TIMEFRAMES InpInterval         = PERIOD_M3; // Candle interval
input int             InpBBLength         = 100;       // Bollinger length
input double          InpBBStd            = 2.0;       // Bollinger standard deviations
input double          InpBBLongThreshold  = 0.0;       // Long when %B is below
input double          InpBBShortThreshold = 1.0;       // Short when %B is above
input group "DCA ladder"
input string          InpDCASpreads        = "0.001,0.018,0.15,0.25"; // DCA spreads (x BB width/200 when dynamic)
input string          InpDCAAmountsPct     = "";      // DCA amount weights (empty = equal)
input bool            InpDynamicOrderSpread = false;  // Scale spreads by Bollinger bandwidth
input bool            InpDynamicTarget     = false;   // Scale stop loss and trailing stop too
input double          InpActivationBounds  = 0.0;     // Only place orders within this distance (0 = off)

class CDManV3Controller : public CHbDirectionalController
  {
protected:
   double            m_spreads[];
   double            m_weights[];
   double            m_bb_width;

   double            SpreadMultiplier(void) const
     {
      return InpDynamicOrderSpread ? m_bb_width / 200.0 : 1.0;
     }
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
      int last = ArraySize(close) - 1;
      if(!HbValid(bbp[last]))
         return;
      m_bb_width = bbb[last];
      if(bbp[last] < InpBBLongThreshold)
         m_signal = 1;
      else
         if(bbp[last] > InpBBShortThreshold)
            m_signal = -1;
      m_signal_info = StringFormat("| %%B %.3f width %.3f%%", bbp[last], m_bb_width);
     }
   virtual CHbExecutor *CreateExecutor(const ENUM_HB_SIDE side, const double price, const double lots)
     {
      int n = ArraySize(m_spreads);
      double total_w = 0;
      for(int i = 0; i < n; i++)
         total_w += m_weights[i];
      double mult = SpreadMultiplier();
      double prices[], level_lots[];
      ArrayResize(prices, n);
      ArrayResize(level_lots, n);
      for(int i = 0; i < n; i++)
        {
         prices[i] = side == HB_BUY ? price * (1.0 - m_spreads[i] * mult) : price * (1.0 + m_spreads[i] * mult);
         level_lots[i] = lots * m_weights[i] / total_w;
        }
      double sl = m_tb.stop_loss, act = m_tb.trailing_activation, delta = m_tb.trailing_delta;
      if(InpDynamicTarget)
        {
         sl *= mult;
         act *= mult;
         delta *= mult;
        }
      CHbDCAExecutor *e = new CHbDCAExecutor();
      e.Setup(m_symbol, side, prices, level_lots, 0.0, sl, act, delta, m_tb.time_limit, InpActivationBounds, "dman_v3");
      return e;
     }

public:
   bool              ConfigureDCA(void)
     {
      m_bb_width = 0;
      int n = HbParseList(InpDCASpreads, m_spreads);
      if(n == 0)
         return false;
      if(HbParseList(InpDCAAmountsPct, m_weights) == 0)
        {
         ArrayResize(m_weights, n);
         ArrayInitialize(m_weights, 1.0);
        }
      return ArraySize(m_weights) == n;
     }
  };

CDManV3Controller g_ctrl;

int OnInit()
  {
   g_hb_verbose = InpVerbose;
   HbInit("DMan-V3", InpMagic, InpDeviation);
   if(!HbCheckAccount())
      return INIT_FAILED;
   if(InpBBLength < 2 || InpTotalLots <= 0)
      return INIT_PARAMETERS_INCORRECT;
   g_ctrl.SetIdentity("dman_v3", _Symbol);
   g_ctrl.ConfigureDirectional(InpTotalLots, InpMaxExecutorsPerSide, InpCooldownTime, InpStopLoss, InpTakeProfit,
                               InpTimeLimit, InpTakeProfitOrderType, InpTrailingActivation, InpTrailingDelta);
   if(!g_ctrl.ConfigureDCA())
     {
      Print("DCA spreads and amounts must be non-empty lists of the same length");
      return INIT_PARAMETERS_INCORRECT;
     }
   g_ctrl.Load();
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason) { HbFinishController(&g_ctrl, reason, InpCancelOnRemove); }
void OnTick()  { g_ctrl.Run(); }
void OnTimer() { g_ctrl.Run(); }

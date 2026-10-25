//+------------------------------------------------------------------+
//| HB_BollinGrid.mq5                                                |
//| Hummingbot controllers/directional_trading/bollingrid            |
//+------------------------------------------------------------------+
#property copyright   "Hummingbot strategies ported to MQL5 - Apache-2.0"
#property version     "1.00"
#property description "BollinGrid (Hummingbot bollingrid): a Bollinger signal launches a grid sized by the bandwidth."

#define HB_DEFAULT_MAGIC 710105
#include <Hummingbot\CommonInputs.mqh>
#include <Hummingbot\Controllers.mqh>
#include <Hummingbot\DirectionalInputs.mqh>

input group "Bollinger Bands"
input ENUM_TIMEFRAMES    InpInterval         = PERIOD_M3; // Candle interval
input int                InpBBLength         = 100;       // Bollinger length
input double             InpBBStd            = 2.0;       // Bollinger standard deviations
input double             InpBBLongThreshold  = 0.0;       // Long when %B is below
input double             InpBBShortThreshold = 1.0;       // Short when %B is above
input group "Grid"
input double             InpGridStartCoef    = 0.25;      // Grid start = close -/+ width x coefficient
input double             InpGridEndCoef      = 0.75;      // Grid end = close +/- width x coefficient
input double             InpGridLimitCoef    = 0.35;      // Grid limit (stop) = close -/+ width x coefficient
input double             InpMinSpreadBetweenOrders = 0.005; // Min spread between levels
input int                InpOrderFrequency   = 2;         // Seconds between order batches
input int                InpMaxOrdersPerBatch = 1;        // Orders per batch
input double             InpMinOrderLots     = 0.0;       // Min lots per level (0 = broker minimum)
input int                InpMaxOpenOrders    = 5;         // Max resting entry orders
input ENUM_HB_ORDER_TYPE InpGridOpenOrderType = HB_ORDER_MARKET; // Level entry type (Hummingbot uses the controller's MARKET)

class CBollinGridController : public CHbDirectionalController
  {
protected:
   double            m_close;
   double            m_width;

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
      m_close = close[last];
      m_width = bbb[last] / 100.0;
      if(bbp[last] < InpBBLongThreshold)
         m_signal = 1;
      else
         if(bbp[last] > InpBBShortThreshold)
            m_signal = -1;
      m_signal_info = StringFormat("| %%B %.3f width %.3f%%", bbp[last], m_width * 100.0);
     }
   virtual CHbExecutor *CreateExecutor(const ENUM_HB_SIDE side, const double price, const double lots)
     {
      double start, end, limit;
      if(side == HB_SELL)
        {
         end = m_close * (1.0 + m_width * InpGridStartCoef);
         start = m_close * (1.0 - m_width * InpGridEndCoef);
         limit = m_close * (1.0 + m_width * InpGridLimitCoef);
        }
      else
        {
         start = m_close * (1.0 - m_width * InpGridStartCoef);
         end = m_close * (1.0 + m_width * InpGridEndCoef);
         limit = m_close * (1.0 - m_width * InpGridLimitCoef);
        }
      if(start <= 0 || end <= start)
         return NULL;
      HbTripleBarrier tb = m_tb;
      tb.open_order_type = InpGridOpenOrderType;
      CHbGridExecutor *e = new CHbGridExecutor();
      e.Setup(m_symbol, side, start, end, limit, lots, InpMinOrderLots, HbTuneDist(InpMinSpreadBetweenOrders), InpMaxOpenOrders,
              InpMaxOrdersPerBatch, InpOrderFrequency, 0.0, tb, false, "bollingrid");
      return e;
     }

public:
                     CBollinGridController(void) { m_close = 0; m_width = 0; }
  };

CBollinGridController g_ctrl;

int OnInit()
  {
   g_hb_verbose = InpVerbose;
   HbInit("BollinGrid", InpMagic, InpDeviation);
   if(!HbCheckAccount())
      return INIT_FAILED;
   if(InpBBLength < 2 || InpTotalLots <= 0 || InpMinSpreadBetweenOrders <= 0)
      return INIT_PARAMETERS_INCORRECT;
   g_ctrl.SetIdentity("bollingrid", _Symbol);
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

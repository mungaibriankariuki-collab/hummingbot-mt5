//+------------------------------------------------------------------+
//| HB_Grid_Strike.mq5                                               |
//| Hummingbot controllers/generic/grid_strike                       |
//+------------------------------------------------------------------+
#property copyright   "Hummingbot strategies ported to MQL5 - Apache-2.0"
#property version     "1.00"
#property description "Grid Strike (Hummingbot grid_strike): one-sided grid between a start and end price."
#property description "Each level buys (or sells) with a limit order and exits at its own take profit."
#property description "Leave the prices at 0 to centre a grid on the current price."

#define HB_DEFAULT_MAGIC 710301
#include <Hummingbot\CommonInputs.mqh>
#include <Hummingbot\Controllers.mqh>
#include <Hummingbot\GridInputs.mqh>

input group "Grid range"
input ENUM_HB_SIDE InpSide         = HB_BUY; // Grid side
input double       InpStartPrice   = 0.0;    // Start (bottom) price, 0 = auto
input double       InpEndPrice     = 0.0;    // End (top) price, 0 = auto
input double       InpLimitPrice   = 0.0;    // Limit (stop-out) price beyond the losing edge, 0 = auto
input double       InpAutoRangePct = 0.02;   // Auto range: +/- this fraction around the mid price (auto-tuned)

class CGridStrikeController : public CHbController
  {
protected:
   double            m_start;
   double            m_end;
   double            m_limit;
   HbTripleBarrier   m_tb;

   bool              InsideBounds(const double price) const { return m_start <= price && price <= m_end; }
   void              ResolveRange(void)
     {
      if(m_start > 0 && m_end > 0)
         return;
      double mid = HbMid(m_symbol);
      if(mid <= 0)
         return;
      double range = HbTune(InpAutoRangePct);
      m_start = InpStartPrice > 0 ? InpStartPrice : HbNormPrice(m_symbol, mid * (1.0 - range));
      m_end = InpEndPrice > 0 ? InpEndPrice : HbNormPrice(m_symbol, mid * (1.0 + range));
      if(InpLimitPrice > 0)
         m_limit = InpLimitPrice;
      else
         m_limit = InpSide == HB_BUY ? HbNormPrice(m_symbol, m_start * (1.0 - range / 2.0))
                                     : HbNormPrice(m_symbol, m_end * (1.0 + range / 2.0));
      HbLog(StringFormat("grid range %s - %s, limit %s", DoubleToString(m_start, _Digits),
                         DoubleToString(m_end, _Digits), DoubleToString(m_limit, _Digits)));
     }
   virtual void      DetermineActions(void)
     {
      ResolveRange();
      if(m_start <= 0 || m_end <= m_start)
         return;
      if(CountActive() == 0 && InsideBounds(HbMid(m_symbol)))
        {
         CHbGridExecutor *e = new CHbGridExecutor();
         e.Setup(m_symbol, InpSide, m_start, m_end, m_limit, InpTotalLots, InpMinOrderLots, HbTuneDist(InpMinSpreadBetweenOrders),
                 InpMaxOpenOrders, InpMaxOrdersPerBatch, InpOrderFrequency, HbTune(InpActivationBounds), m_tb,
                 InpKeepPosition, "grid");
         AddExecutor(e);
        }
     }
   virtual string    StatusHeader(void)
     {
      double mid = HbMid(m_symbol);
      return StringFormat("start %s | end %s | side %s | limit %s | mid %s | inside bounds %d",
                          DoubleToString(m_start, _Digits), DoubleToString(m_end, _Digits), HbSideName(InpSide),
                          DoubleToString(m_limit, _Digits), DoubleToString(mid, _Digits), InsideBounds(mid) ? 1 : 0);
     }

public:
                     CGridStrikeController(void) { m_start = 0; m_end = 0; m_limit = 0; m_tb.Init(); }
   void              Configure(void)
     {
      HbGridBarrier(m_tb);
      m_start = InpStartPrice;
      m_end = InpEndPrice;
      m_limit = InpLimitPrice;
     }
   // auto-placed ranges are kept across restarts
   virtual void      SaveExtra(const int h)
     {
      FileWriteDouble(h, m_start);
      FileWriteDouble(h, m_end);
      FileWriteDouble(h, m_limit);
     }
   virtual void      LoadExtra(const int h)
     {
      double s = FileReadDouble(h), e = FileReadDouble(h), l = FileReadDouble(h);
      if(InpStartPrice <= 0 && InpEndPrice <= 0 && s > 0 && e > s)
        {
         m_start = s;
         m_end = e;
         m_limit = InpLimitPrice > 0 ? InpLimitPrice : l;
        }
     }
  };

CGridStrikeController g_ctrl;

int OnInit()
  {
   g_hb_verbose = InpVerbose;
   HbInit("GridStrike", InpMagic, InpDeviation);
   if(!HbCheckAccount())
      return INIT_FAILED;
   if(InpTotalLots <= 0 || InpMinSpreadBetweenOrders <= 0 || InpMaxOpenOrders < 1 ||
      (InpStartPrice > 0 && InpEndPrice > 0 && InpEndPrice <= InpStartPrice))
      return INIT_PARAMETERS_INCORRECT;
   HbAutoTune(_Symbol);
   g_ctrl.SetIdentity("grid_strike", _Symbol);
   g_ctrl.Configure();
   g_ctrl.Load();
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason) { HbFinishController(&g_ctrl, reason, InpCancelOnRemove); }
void OnTick()  { g_ctrl.Run(); }
void OnTimer() { g_ctrl.Run(); }

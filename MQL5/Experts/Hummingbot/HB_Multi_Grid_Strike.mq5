//+------------------------------------------------------------------+
//| HB_Multi_Grid_Strike.mq5                                         |
//| Hummingbot controllers/generic/multi_grid_strike                 |
//+------------------------------------------------------------------+
#property copyright   "Hummingbot strategies ported to MQL5 - Apache-2.0"
#property version     "1.00"
#property description "Multi Grid Strike (Hummingbot multi_grid_strike): up to three independent grids on one symbol."
#property description "Each grid gets a share of the total lots and starts when the price is inside its range."

#define HB_DEFAULT_MAGIC 710302
#include <Hummingbot\CommonInputs.mqh>
#include <Hummingbot\Controllers.mqh>
#include <Hummingbot\GridInputs.mqh>

input group "Grid 1"
input bool         InpG1Enabled = true;   // Enabled
input ENUM_HB_SIDE InpG1Side    = HB_BUY; // Side
input double       InpG1Start   = 0.0;    // Start price
input double       InpG1End     = 0.0;    // End price
input double       InpG1Limit   = 0.0;    // Limit price (0 = off)
input double       InpG1Pct     = 0.5;    // Share of total lots (0-1)
input group "Grid 2"
input bool         InpG2Enabled = false;   // Enabled
input ENUM_HB_SIDE InpG2Side    = HB_SELL; // Side
input double       InpG2Start   = 0.0;     // Start price
input double       InpG2End     = 0.0;     // End price
input double       InpG2Limit   = 0.0;     // Limit price (0 = off)
input double       InpG2Pct     = 0.5;     // Share of total lots (0-1)
input group "Grid 3"
input bool         InpG3Enabled = false;  // Enabled
input ENUM_HB_SIDE InpG3Side    = HB_BUY; // Side
input double       InpG3Start   = 0.0;    // Start price
input double       InpG3End     = 0.0;    // End price
input double       InpG3Limit   = 0.0;    // Limit price (0 = off)
input double       InpG3Pct     = 0.0;    // Share of total lots (0-1)

struct HbGridSlot
  {
   string            id;
   bool              enabled;
   ENUM_HB_SIDE      side;
   double            start;
   double            end;
   double            limit;
   double            pct;
  };

class CMultiGridController : public CHbController
  {
protected:
   HbGridSlot        m_grids[3];
   HbTripleBarrier   m_tb;

   void              SetSlot(const int i, const string id, const bool enabled, const ENUM_HB_SIDE side,
                             const double start, const double end, const double limit, const double pct)
     {
      m_grids[i].id = id;
      m_grids[i].enabled = enabled && start > 0 && end > start && pct > 0;
      m_grids[i].side = side;
      m_grids[i].start = start;
      m_grids[i].end = end;
      m_grids[i].limit = limit;
      m_grids[i].pct = pct;
      if(enabled && !m_grids[i].enabled)
         Print(id, ": needs start > 0, end > start and a positive share; grid disabled");
     }
   virtual void      DetermineActions(void)
     {
      double mid = HbMid(m_symbol);
      for(int g = 0; g < 3; g++)
        {
         // disabled or removed grids stop their executor
         if(!m_grids[g].enabled)
           {
            for(int i = 0; i < m_executors.Total(); i++)
              {
               CHbExecutor *e = (CHbExecutor *)m_executors.At(i);
               if(e != NULL && e.Status() == HB_RUNNING && e.LevelId() == m_grids[g].id)
                  e.EarlyStop(InpKeepPosition);
              }
            continue;
           }
         if(CountActive(0, m_grids[g].id) > 0)
            continue;
         if(mid < m_grids[g].start || mid > m_grids[g].end)
            continue;
         CHbGridExecutor *ex = new CHbGridExecutor();
         ex.Setup(m_symbol, m_grids[g].side, m_grids[g].start, m_grids[g].end, m_grids[g].limit,
                  InpTotalLots * m_grids[g].pct, InpMinOrderLots, InpMinSpreadBetweenOrders, InpMaxOpenOrders,
                  InpMaxOrdersPerBatch, InpOrderFrequency, InpActivationBounds, m_tb, InpKeepPosition, m_grids[g].id);
         AddExecutor(ex);
        }
     }
   virtual string    StatusHeader(void)
     {
      string s = "";
      double mid = HbMid(m_symbol);
      for(int g = 0; g < 3; g++)
        {
         if(!m_grids[g].enabled)
            continue;
         s += StringFormat("%s %s %s-%s share %.0f%% inside %d | ", m_grids[g].id, HbSideName(m_grids[g].side),
                           DoubleToString(m_grids[g].start, _Digits), DoubleToString(m_grids[g].end, _Digits),
                           m_grids[g].pct * 100.0, (mid >= m_grids[g].start && mid <= m_grids[g].end) ? 1 : 0);
        }
      return s;
     }

public:
   void              Configure(void)
     {
      HbGridBarrier(m_tb);
      SetSlot(0, "grid_1", InpG1Enabled, InpG1Side, InpG1Start, InpG1End, InpG1Limit, InpG1Pct);
      SetSlot(1, "grid_2", InpG2Enabled, InpG2Side, InpG2Start, InpG2End, InpG2Limit, InpG2Pct);
      SetSlot(2, "grid_3", InpG3Enabled, InpG3Side, InpG3Start, InpG3End, InpG3Limit, InpG3Pct);
     }
  };

CMultiGridController g_ctrl;

int OnInit()
  {
   g_hb_verbose = InpVerbose;
   HbInit("MultiGridStrike", InpMagic, InpDeviation);
   if(!HbCheckAccount())
      return INIT_FAILED;
   if(InpTotalLots <= 0 || InpMinSpreadBetweenOrders <= 0 || InpMaxOpenOrders < 1)
      return INIT_PARAMETERS_INCORRECT;
   g_ctrl.SetIdentity("multi_grid_strike", _Symbol);
   g_ctrl.Configure();
   g_ctrl.Load();
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason) { HbFinishController(&g_ctrl, reason, InpCancelOnRemove); }
void OnTick()  { g_ctrl.Run(); }
void OnTimer() { g_ctrl.Run(); }

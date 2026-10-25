//+------------------------------------------------------------------+
//| HB_DMan_Maker_V2.mq5                                             |
//| Hummingbot controllers/market_making/dman_maker_v2               |
//+------------------------------------------------------------------+
#property copyright   "Hummingbot strategies ported to MQL5 - Apache-2.0"
#property version     "1.00"
#property description "D-Man Maker V2 (Hummingbot dman_maker_v2): market making where each level is a DCA ladder."
#property description "Stops and take profit work on the ladder's average entry price."

#define HB_DEFAULT_MAGIC 710203
#include <Hummingbot\CommonInputs.mqh>
#include <Hummingbot\Controllers.mqh>
#include <Hummingbot\MarketMakingInputs.mqh>

input group "DCA ladder per level"
input string InpDCASpreads             = "0.01,0.02,0.04,0.08"; // DCA spreads from the level price
input string InpDCAAmounts             = "0.1,0.2,0.4,0.8";     // DCA amount weights
input int    InpTopExecutorRefreshTime = 0;     // Refresh level 0 sooner (seconds, 0 = off)
input double InpExecutorActivationBounds = 0.0; // Only place orders within this distance (0 = off)

class CDManMakerV2Controller : public CHbMarketMakingController
  {
protected:
   double            m_dca_spreads[];
   double            m_dca_pct[];

   virtual CHbExecutor *CreateExecutor(const string level_id, const ENUM_HB_SIDE side, const double price,
                                       const double lots)
     {
      int n = ArraySize(m_dca_spreads);
      double prices[], level_lots[];
      ArrayResize(prices, n);
      ArrayResize(level_lots, n);
      for(int i = 0; i < n; i++)
        {
         prices[i] = side == HB_BUY ? price * (1.0 - m_dca_spreads[i]) : price * (1.0 + m_dca_spreads[i]);
         level_lots[i] = lots * m_dca_pct[i];
        }
      CHbDCAExecutor *e = new CHbDCAExecutor();
      e.Setup(m_symbol, side, prices, level_lots, m_tb.take_profit, m_tb.stop_loss, m_tb.trailing_activation,
              m_tb.trailing_delta, m_tb.time_limit, InpExecutorActivationBounds, level_id);
      return e;
     }
   virtual bool      RefreshCondition(CHbExecutor *e)
     {
      if(e.IsTrading())
         return false;
      long age = (long)(HbNow() - e.Timestamp());
      if(age > m_refresh_time)
         return true;
      if(InpTopExecutorRefreshTime > 0 && StringFind(e.LevelId(), "_0") == StringLen(e.LevelId()) - 2)
         return age > InpTopExecutorRefreshTime;
      return false;
     }

public:
   bool              ConfigureDCA(void)
     {
      int n = HbParseList(InpDCASpreads, m_dca_spreads);
      double amounts[];
      int m = HbParseList(InpDCAAmounts, amounts);
      if(n == 0)
         return false;
      if(m == 0)
        {
         ArrayResize(amounts, n);
         ArrayInitialize(amounts, 1.0);
         m = n;
        }
      if(m != n)
         return false;
      double total = 0;
      for(int i = 0; i < n; i++)
         total += amounts[i];
      if(total <= 0)
         return false;
      ArrayResize(m_dca_pct, n);
      for(int i = 0; i < n; i++)
         m_dca_pct[i] = amounts[i] / total;
      return true;
     }
  };

CDManMakerV2Controller g_ctrl;

int OnInit()
  {
   g_hb_verbose = InpVerbose;
   HbInit("DMan-Maker-V2", InpMagic, InpDeviation);
   if(!HbCheckAccount())
      return INIT_FAILED;
   g_ctrl.SetIdentity("dman_maker_v2", _Symbol);
   if(InpTotalLots <= 0 ||
      !g_ctrl.ConfigureMarketMaking(InpBuySpreads, InpSellSpreads, InpBuyAmountsPct, InpSellAmountsPct, InpTotalLots,
                                    InpExecutorRefreshTime, InpCooldownTime, InpStopLoss, InpTakeProfit, InpTimeLimit,
                                    InpTakeProfitOrderType, InpTrailingActivation, InpTrailingDelta))
      return INIT_PARAMETERS_INCORRECT;
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

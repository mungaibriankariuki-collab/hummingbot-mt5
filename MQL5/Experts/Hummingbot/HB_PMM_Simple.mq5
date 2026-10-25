//+------------------------------------------------------------------+
//| HB_PMM_Simple.mq5                                                |
//| Hummingbot controllers/market_making/pmm_simple                  |
//+------------------------------------------------------------------+
#property copyright   "Hummingbot strategies ported to MQL5 - Apache-2.0"
#property version     "1.00"
#property description "Pure market making (Hummingbot pmm_simple): limit orders at fixed spreads around the mid price."
#property description "Every filled level is managed with stop loss, take profit, time limit and trailing stop."

#define HB_DEFAULT_MAGIC 710201
#include <Hummingbot\CommonInputs.mqh>
#include <Hummingbot\Controllers.mqh>
#include <Hummingbot\MarketMakingInputs.mqh>

class CPMMSimpleController : public CHbMarketMakingController
  {
  };

CPMMSimpleController g_ctrl;

int OnInit()
  {
   g_hb_verbose = InpVerbose;
   HbInit("PMM-Simple", InpMagic, InpDeviation);
   if(!HbCheckAccount())
      return INIT_FAILED;
   HbAutoTune(_Symbol);
   g_ctrl.SetIdentity("pmm_simple", _Symbol);
   if(InpTotalLots <= 0 ||
      !g_ctrl.ConfigureMarketMaking(HbTuneList(InpBuySpreads, true), HbTuneList(InpSellSpreads, true), InpBuyAmountsPct, InpSellAmountsPct, InpTotalLots,
                                    InpExecutorRefreshTime, InpCooldownTime, HbTuneDist(InpStopLoss),
                                    HbTuneDist(InpTakeProfit), InpTimeLimit, InpTakeProfitOrderType,
                                    HbTuneDist(InpTrailingActivation), HbTuneDist(InpTrailingDelta)))
      return INIT_PARAMETERS_INCORRECT;
   g_ctrl.Load();
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason) { HbFinishController(&g_ctrl, reason, InpCancelOnRemove); }
void OnTick()  { g_ctrl.Run(); }
void OnTimer() { g_ctrl.Run(); }

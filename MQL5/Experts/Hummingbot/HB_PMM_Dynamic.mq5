//+------------------------------------------------------------------+
//| HB_PMM_Dynamic.mq5                                               |
//| Hummingbot controllers/market_making/pmm_dynamic                 |
//+------------------------------------------------------------------+
#property copyright   "Hummingbot strategies ported to MQL5 - Apache-2.0"
#property version     "1.00"
#property description "Dynamic market making (Hummingbot pmm_dynamic): MACD shifts the reference price and NATR scales the spreads."
#property description "Spreads are multiples of NATR, e.g. 1,2,4 = 1x, 2x and 4x the normalised ATR, so auto-tune leaves them as entered."

#define HB_DEFAULT_MAGIC 710202
#define HB_DEF_BUY_SPREADS "1,2,4"
#define HB_DEF_SELL_SPREADS "1,2,4"
#include <Hummingbot\CommonInputs.mqh>
#include <Hummingbot\Controllers.mqh>
#include <Hummingbot\MarketMakingInputs.mqh>

input group "Indicators"
input ENUM_TIMEFRAMES InpInterval   = PERIOD_M3; // Candle interval
input int             InpMACDFast   = 21;        // MACD fast period
input int             InpMACDSlow   = 42;        // MACD slow period
input int             InpMACDSignal = 9;         // MACD signal period
input int             InpNATRLength = 14;        // NATR length

class CPMMDynamicController : public CHbMarketMakingController
  {
protected:
   double            m_natr;
   double            m_price_shift;

   virtual void      UpdateProcessedData(void)
     {
      m_reference_price = 0;
      int records = (int)MathMax(MathMax(InpMACDSlow, InpMACDFast), MathMax(InpMACDSignal, InpNATRLength)) + 100;
      double open[], high[], low[], close[];
      if(!HbGetCandles(m_symbol, InpInterval, records, open, high, low, close))
         return;
      double natr[];
      HbNATR(high, low, close, InpNATRLength, natr);
      double macd[], macds[], macdh[];
      HbMACD(close, InpMACDFast, InpMACDSlow, InpMACDSignal, macd, macds, macdh);
      int last = ArraySize(close) - 1;
      if(!HbValid(natr[last]) || !HbValid(macdh[last]))
         return;
      // z-score of the MACD line over the window (pandas mean/std, ddof=1), inverted
      double valid[];
      int n = HbValidTail(macd, valid);
      if(n < 2)
         return;
      double mean = HbMean(valid);
      double var = 0;
      for(int i = 0; i < n; i++)
         var += (valid[i] - mean) * (valid[i] - mean);
      double sd = MathSqrt(var / (n - 1));
      double macd_signal = sd > 0 ? -(macd[last] - mean) / sd : 0.0;
      double macdh_signal = macdh[last] > 0 ? 1.0 : -1.0;
      double max_price_shift = natr[last] / 2.0;
      m_price_shift = (0.5 * macd_signal + 0.5 * macdh_signal) * max_price_shift;
      m_natr = natr[last];
      m_reference_price = close[last] * (1.0 + m_price_shift);
      m_spread_multiplier = m_natr;
     }
   virtual string    StatusHeader(void)
     {
      return CHbMarketMakingController::StatusHeader() +
             StringFormat(" | NATR %.4f%% | shift %.4f%%", m_natr * 100.0, m_price_shift * 100.0);
     }

public:
                     CPMMDynamicController(void) { m_natr = 0; m_price_shift = 0; }
  };

CPMMDynamicController g_ctrl;

int OnInit()
  {
   g_hb_verbose = InpVerbose;
   HbInit("PMM-Dynamic", InpMagic, InpDeviation);
   if(!HbCheckAccount())
      return INIT_FAILED;
   if(InpMACDFast < 1 || InpMACDSlow <= InpMACDFast || InpMACDSignal < 1 || InpNATRLength < 1)
      return INIT_PARAMETERS_INCORRECT;
   HbAutoTune(_Symbol);
   g_ctrl.SetIdentity("pmm_dynamic", _Symbol);
   if(InpTotalLots <= 0 ||
      !g_ctrl.ConfigureMarketMaking(InpBuySpreads, InpSellSpreads, InpBuyAmountsPct, InpSellAmountsPct, InpTotalLots,
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

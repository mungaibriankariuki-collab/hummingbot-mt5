//+------------------------------------------------------------------+
//| HB_Stat_Arb.mq5                                                  |
//| Hummingbot controllers/generic/stat_arb                          |
//+------------------------------------------------------------------+
#property copyright   "Hummingbot strategies ported to MQL5 - Apache-2.0"
#property version     "1.00"
#property description "Statistical arbitrage (Hummingbot stat_arb) between two correlated symbols."
#property description "Regresses cumulative returns, trades the z-score of the spread: z > threshold = long dominant / short hedge."
#property description "Sizes are account-currency notional so both legs stay balanced by the hedge ratio."

#define HB_DEFAULT_MAGIC 710501
#include <Hummingbot\CommonInputs.mqh>
#include <Hummingbot\Controllers.mqh>

input group "Pair"
input string          InpDominantSymbol = "";        // Dominant symbol (empty = chart symbol)
input string          InpHedgeSymbol    = "";        // Hedge symbol (required)
input ENUM_TIMEFRAMES InpInterval       = PERIOD_M1; // Candle interval
input int             InpLookbackPeriod = 300;       // Lookback period (candles)
input double          InpEntryThreshold = 2.0;       // Z-score entry threshold
input group "Sizing (account currency notional)"
input double          InpTotalAmount          = 10000; // Total amount (total_amount_quote)
input double          InpMinAmount            = 1000;  // Amount per order (min_amount_quote)
input double          InpPosHedgeRatio        = 1.0;   // Position hedge ratio
input double          InpMaxPositionDeviation = 0.1;   // Max imbalance between legs (0.1 = 10%)
input group "Quoting"
input double          InpQuoterSpread           = 0.0001; // Quote distance from the best placed price
input int             InpQuoterCooldown         = 30;     // Hold filled orders as position after (seconds)
input int             InpQuoterRefresh          = 10;     // Refresh unfilled orders after (seconds)
input int             InpMaxOrdersPlacedPerSide = 2;      // Max resting orders per leg
input int             InpMaxOrdersFilledPerSide = 2;      // Max filled executors per leg
input group "Risk"
input double          InpTakeProfit = 0.0008; // Take profit per order (0.0008 = 0.08%)
input double          InpTpGlobal   = 0.01;   // Close the pair at this total profit (1%)
input double          InpSlGlobal   = 0.05;   // Close the pair at this total loss (5%)

class CStatArbController : public CHbController
  {
protected:
   string            m_dom;
   string            m_hedge;
   HbTripleBarrier   m_tb;
   double            m_theo_dom;
   double            m_theo_hedge;
   bool              m_have_z;
   double            m_z;
   double            m_spread;
   double            m_alpha;
   double            m_beta;
   int               m_signal;
   double            m_pair_pnl_pct;
   double            m_dom_gap;
   double            m_hedge_gap;
   double            m_imbalance_pct;
   int               m_filter; // 0 none, 1 skip dominant, 2 skip hedge

   bool              ZScore(void)
     {
      double dom[], hed[];
      if(!HbGetCloses(m_dom, InpInterval, InpLookbackPeriod, dom) || !HbGetCloses(m_hedge, InpInterval, InpLookbackPeriod, hed))
         return false;
      int n = MathMin(ArraySize(dom), ArraySize(hed));
      if(n < 3)
         return false;
      // cumulative returns, normalised to start at 1
      int m = n - 1;
      double cd[], ch[];
      ArrayResize(cd, m);
      ArrayResize(ch, m);
      double pd = 1, ph = 1;
      for(int i = 1; i < n; i++)
        {
         pd *= dom[i] / dom[i - 1];
         ph *= hed[i] / hed[i - 1];
         cd[i - 1] = pd;
         ch[i - 1] = ph;
        }
      double d0 = cd[0], h0 = ch[0];
      for(int i = 0; i < m; i++)
        {
         cd[i] /= d0;
         ch[i] /= h0;
        }
      if(!HbLinReg(cd, ch, m_alpha, m_beta))
         return false;
      double spread[];
      ArrayResize(spread, m);
      for(int i = 0; i < m; i++)
        {
         double pred = m_alpha + m_beta * cd[i];
         spread[i] = pred != 0 ? (ch[i] - pred) / pred * 100.0 : 0;
        }
      double sd = HbStd(spread);
      if(sd == 0)
         return false;
      m_spread = spread[m - 1];
      m_z = (m_spread - HbMean(spread)) / sd;
      return true;
     }
   bool              IsOwned(const ulong id, const ulong &owned[])
     {
      for(int i = 0; i < ArraySize(owned); i++)
         if(owned[i] == id)
            return true;
      return false;
     }
   // Held positions: open positions of this EA that no running executor manages
   void              HeldPosition(const string sym, const int side, const ulong &owned[], double &notional, double &pnl)
     {
      double n_buy = 0, p_buy = 0, n_sell = 0, p_sell = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0 || PositionGetInteger(POSITION_MAGIC) != g_hb_magic || PositionGetString(POSITION_SYMBOL) != sym)
            continue;
         if(IsOwned((ulong)PositionGetInteger(POSITION_IDENTIFIER), owned))
            continue;
         double v = PositionGetDouble(POSITION_VOLUME) * HbLotNotional(sym, PositionGetDouble(POSITION_PRICE_CURRENT));
         double p = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
           {
            n_buy += v;
            p_buy += p;
           }
         else
           {
            n_sell += v;
            p_sell += p;
           }
        }
      if(side > 0 || (side == 0 && n_buy > 0))
        {
         notional = n_buy;
         pnl = p_buy;
        }
      else
        {
         notional = n_sell;
         pnl = p_sell;
        }
     }
   void              CloseHeld(const string sym, const int side, const ulong &owned[])
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0 || PositionGetInteger(POSITION_MAGIC) != g_hb_magic || PositionGetString(POSITION_SYMBOL) != sym)
            continue;
         if(IsOwned((ulong)PositionGetInteger(POSITION_IDENTIFIER), owned))
            continue;
         int s = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
         if(side == 0 || s == side)
            g_hb_trade.PositionClose(t);
        }
     }
   void              ExecutorStats(const string sym, int &placed, int &filled, double &min_price, double &max_price,
                                   double &active_amount)
     {
      placed = 0; filled = 0; min_price = 0; max_price = 0; active_amount = 0;
      for(int i = 0; i < m_executors.Total(); i++)
        {
         CHbExecutor *e = (CHbExecutor *)m_executors.At(i);
         if(e == NULL || !e.IsActive() || e.Sym() != sym || e.ExecType() != HB_EXEC_POSITION)
            continue;
         CHbPositionExecutor *pe = (CHbPositionExecutor *)e;
         if(pe.IsTrading())
           {
            filled++;
            active_amount += pe.FilledNotional();
           }
         else
           {
            placed++;
            double p = pe.EntryPrice();
            if(min_price == 0 || p < min_price)
               min_price = p;
            if(p > max_price)
               max_price = p;
           }
        }
     }
   void              StopExecutors(const string sym, const int side, const bool keep_position, const bool only_trading,
                                   const bool only_placed, const int min_age)
     {
      datetime now = HbNow();
      for(int i = 0; i < m_executors.Total(); i++)
        {
         CHbExecutor *e = (CHbExecutor *)m_executors.At(i);
         if(e == NULL || e.Status() != HB_RUNNING || e.Sym() != sym)
            continue;
         if(side != 0 && (int)e.Side() != side)
            continue;
         if(only_trading && !e.IsTrading())
            continue;
         if(only_placed && e.IsTrading())
            continue;
         if(now - e.Timestamp() < min_age)
            continue;
         e.EarlyStop(keep_position);
        }
     }
   void              Quote(const string sym, const ENUM_HB_SIDE side, const double min_price, const double max_price,
                           const string level_id)
     {
      double mid = HbMid(sym);
      double ref_min = min_price > 0 ? min_price : mid;
      double ref_max = max_price > 0 ? max_price : mid;
      double price = side == HB_BUY ? ref_min * (1.0 - InpQuoterSpread) : ref_max * (1.0 + InpQuoterSpread);
      double notional = HbLotNotional(sym, mid);
      if(notional <= 0)
         return;
      CHbPositionExecutor *e = new CHbPositionExecutor();
      e.Setup(sym, side, price, InpMinAmount / notional, m_tb, level_id);
      AddExecutor(e);
     }

   virtual void      DetermineActions(void)
     {
      m_have_z = ZScore();
      if(!m_have_z)
        {
         m_signal = 0;
         return;
        }
      m_signal = m_z > InpEntryThreshold ? 1 : (m_z < -InpEntryThreshold ? -1 : 0);
      int dom_side = m_signal, hedge_side = -m_signal;
      ulong owned[];
      for(int i = 0; i < m_executors.Total(); i++)
        {
         CHbExecutor *e = (CHbExecutor *)m_executors.At(i);
         if(e != NULL && e.IsActive())
            e.PositionIds(owned);
        }
      double dom_q, dom_pnl, hed_q, hed_pnl;
      HeldPosition(m_dom, dom_side, owned, dom_q, dom_pnl);
      HeldPosition(m_hedge, hedge_side, owned, hed_q, hed_pnl);
      m_pair_pnl_pct = (dom_q + hed_q) != 0 ? (dom_pnl + hed_pnl) / (dom_q + hed_q) : 0;
      int dom_placed, dom_filled, hed_placed, hed_filled;
      double dom_min, dom_max, dom_active, hed_min, hed_max, hed_active;
      ExecutorStats(m_dom, dom_placed, dom_filled, dom_min, dom_max, dom_active);
      ExecutorStats(m_hedge, hed_placed, hed_filled, hed_min, hed_max, hed_active);
      m_dom_gap = m_theo_dom - dom_q - dom_active;
      m_hedge_gap = m_theo_hedge - hed_q - hed_active;
      double imbalance_scaled = dom_q - hed_q * InpPosHedgeRatio;
      m_imbalance_pct = dom_q != 0 ? imbalance_scaled / dom_q : 0;
      m_filter = m_imbalance_pct > InpMaxPositionDeviation ? 1 : (m_imbalance_pct < -InpMaxPositionDeviation ? 2 : 0);

      // global take profit / stop loss on the held pair
      if(m_pair_pnl_pct > InpTpGlobal || m_pair_pnl_pct < -InpSlGlobal)
        {
         HbLog(StringFormat("pair pnl %.3f%% hit the global target, closing held positions", m_pair_pnl_pct * 100.0));
         CloseHeld(m_dom, 0, owned);
         CloseHeld(m_hedge, 0, owned);
         return;
        }
      if(m_signal != 0)
        {
         ENUM_HB_SIDE dside = m_signal == 1 ? HB_BUY : HB_SELL;
         ENUM_HB_SIDE hside = m_signal == 1 ? HB_SELL : HB_BUY;
         if(m_dom_gap > 0 && m_filter != 1 && dom_placed < InpMaxOrdersPlacedPerSide && dom_filled < InpMaxOrdersFilledPerSide)
            Quote(m_dom, dside, dom_min, dom_max, "dominant");
         if(m_hedge_gap > 0 && m_filter != 2 && hed_placed < InpMaxOrdersPlacedPerSide && hed_filled < InpMaxOrdersFilledPerSide)
            Quote(m_hedge, hside, hed_min, hed_max, "hedge");
         // unwind the opposite trade
         StopExecutors(m_dom, -(int)dside, false, false, false, 0);
         StopExecutors(m_hedge, -(int)hside, false, false, false, 0);
         CloseHeld(m_dom, -(int)dside, owned);
         CloseHeld(m_hedge, -(int)hside, owned);
        }
      // filled orders become held position after the cooldown; unfilled ones are refreshed
      StopExecutors(m_dom, 0, true, true, false, InpQuoterCooldown);
      StopExecutors(m_hedge, 0, true, true, false, InpQuoterCooldown);
      StopExecutors(m_dom, 0, false, false, true, InpQuoterRefresh);
      StopExecutors(m_hedge, 0, false, false, true, InpQuoterRefresh);
     }
   virtual string    StatusHeader(void)
     {
      if(!m_have_z)
         return StringFormat("%s / %s | waiting for %d candles on both symbols", m_dom, m_hedge, InpLookbackPeriod);
      return StringFormat("%s / %s | z %.2f (entry %.2f) | spread %.3f%% | beta %.3f | signal %d\n"
                          "pair pnl %.3f%% | gap dominant %.0f hedge %.0f | imbalance %.1f%%",
                          m_dom, m_hedge, m_z, InpEntryThreshold, m_spread, m_beta, m_signal,
                          m_pair_pnl_pct * 100.0, m_dom_gap, m_hedge_gap, m_imbalance_pct * 100.0);
     }

public:
                     CStatArbController(void)
     {
      m_theo_dom = 0; m_theo_hedge = 0; m_have_z = false; m_z = 0; m_spread = 0; m_alpha = 0; m_beta = 0;
      m_signal = 0; m_pair_pnl_pct = 0; m_dom_gap = 0; m_hedge_gap = 0; m_imbalance_pct = 0; m_filter = 0;
      m_tb.Init();
     }
   bool              Configure(const string dom, const string hedge)
     {
      m_dom = dom;
      m_hedge = hedge;
      if(!SymbolSelect(m_dom, true) || !SymbolSelect(m_hedge, true))
         return false;
      m_theo_dom = InpTotalAmount * (1.0 / (1.0 + InpPosHedgeRatio));
      m_theo_hedge = InpTotalAmount * (InpPosHedgeRatio / (1.0 + InpPosHedgeRatio));
      m_tb.take_profit = InpTakeProfit;
      m_tb.open_order_type = HB_ORDER_LIMIT_MAKER;
      m_tb.take_profit_order_type = HB_ORDER_LIMIT_MAKER;
      return true;
     }
  };

CStatArbController g_ctrl;

int OnInit()
  {
   g_hb_verbose = InpVerbose;
   HbInit("StatArb", InpMagic, InpDeviation);
   if(!HbCheckAccount())
      return INIT_FAILED;
   string dom = InpDominantSymbol == "" ? _Symbol : InpDominantSymbol;
   if(InpHedgeSymbol == "" || InpHedgeSymbol == dom)
     {
      Alert("Stat Arb: set 'Hedge symbol' to a second, correlated symbol");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLookbackPeriod < 10 || InpTotalAmount <= 0 || InpMinAmount <= 0 || InpPosHedgeRatio <= 0)
      return INIT_PARAMETERS_INCORRECT;
   g_ctrl.SetIdentity("stat_arb", dom);
   if(!g_ctrl.Configure(dom, InpHedgeSymbol))
     {
      Alert("Stat Arb: symbol not found: ", dom, " / ", InpHedgeSymbol);
      return INIT_PARAMETERS_INCORRECT;
     }
   g_ctrl.Load();
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason) { HbFinishController(&g_ctrl, reason, InpCancelOnRemove); }
void OnTick()  { g_ctrl.Run(); }
void OnTimer() { g_ctrl.Run(); }

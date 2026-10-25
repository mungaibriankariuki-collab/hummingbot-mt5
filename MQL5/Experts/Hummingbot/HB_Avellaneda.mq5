//+------------------------------------------------------------------+
//| HB_Avellaneda.mq5                                                |
//| Hummingbot strategy/avellaneda_market_making                     |
//+------------------------------------------------------------------+
#property copyright   "Hummingbot strategies ported to MQL5 - Apache-2.0"
#property version     "1.00"
#property description "Avellaneda-Stoikov market making (Hummingbot avellaneda_market_making, infinite timeframe)."
#property description "Quotes around a reservation price that leans against inventory; spreads widen with volatility."
#property description "Inventory is the EA's net position measured against an inventory size in lots."

#define HB_DEFAULT_MAGIC 710401
#include <Hummingbot\CommonInputs.mqh>
#include <Hummingbot\Controllers.mqh>

input group "Orders"
input double InpOrderAmount              = 0.01;  // Order amount (lots)
input int    InpOrderLevels              = 1;     // Order levels per side (1 = single bid/ask)
input double InpLevelDistances           = 0.0;   // Distance between levels, % of the optimal half spread
input int    InpOrderRefreshTime         = 30;    // Order refresh time (seconds)
input int    InpMaxOrderAge              = 1800;  // Max order age (seconds)
input double InpOrderRefreshTolerancePct = 0.0;   // Keep orders if prices moved less than this % (0 = always refresh)
input int    InpFilledOrderDelay         = 60;    // Wait after a fill before quoting again (seconds)
input group "Model"
input double InpRiskFactor               = 1.0;   // Risk factor (gamma)
input double InpOrderAmountShapeFactor   = 0.0;   // Order amount shape factor (eta)
input double InpMinSpread                = 0.0;   // Minimum spread (% of price)
input double InpKappa                    = 0.0;   // Order book liquidity kappa (0 = derive from the bid/ask spread)
input int    InpVolatilityBufferSize     = 200;   // Volatility samples (1 per second)
input group "Inventory"
input double InpInventoryLots            = 0.1;   // Inventory size in lots (stands in for base + quote balance)
input double InpInventoryTargetBasePct   = 50.0;  // Inventory target base % (50 = flat)
input bool   InpNetPositions             = true;  // Close opposite positions against each other

struct HbQuote
  {
   double            price;
   double            size;
  };

class CAvellanedaController : public CHbController
  {
protected:
   double            m_mid_samples[];
   double            m_spread_samples[];
   ulong             m_tracked[];
   datetime          m_create_ts;
   datetime          m_cancel_ts;
   double            m_net;
   double            m_q;
   double            m_vol;
   double            m_kappa;
   double            m_reservation;
   double            m_optimal_spread;
   double            m_optimal_bid;
   double            m_optimal_ask;
   HbQuote           m_buys[];
   HbQuote           m_sells[];

   void              PushSample(double &buf[], const double v)
     {
      int n = ArraySize(buf);
      if(n < InpVolatilityBufferSize)
        {
         ArrayResize(buf, n + 1);
         buf[n] = v;
         return;
        }
      for(int i = 1; i < n; i++)
         buf[i - 1] = buf[i];
      buf[n - 1] = v;
     }
   bool              IsReady(void) const { return ArraySize(m_mid_samples) >= InpVolatilityBufferSize; }

   // InstantVolatilityIndicator: sqrt(sum(diff^2) / N)
   double            Volatility(void) const
     {
      int n = ArraySize(m_mid_samples);
      if(n < 2)
         return 0;
      double s = 0;
      for(int i = 1; i < n; i++)
         s += (m_mid_samples[i] - m_mid_samples[i - 1]) * (m_mid_samples[i] - m_mid_samples[i - 1]);
      return MathSqrt(s / n);
     }
   double            Kappa(void) const
     {
      if(InpKappa > 0)
         return InpKappa;
      // no public trade flow on most MT5 symbols: choose kappa so the liquidity term equals the average spread
      double avg = HbMean(m_spread_samples);
      if(avg <= 0)
         avg = HbTickSize(m_symbol);
      double denom = MathExp(InpRiskFactor * avg / 2.0) - 1.0;
      return denom > 0 ? InpRiskFactor / denom : 0;
     }
   void              ReadInventory(void)
     {
      m_net = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0 || PositionGetInteger(POSITION_MAGIC) != g_hb_magic || PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;
         double v = PositionGetDouble(POSITION_VOLUME);
         m_net += PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? v : -v;
        }
      // base balance = net + inv/2, so a flat book sits at 50% base
      double inv = InpInventoryLots;
      m_q = inv > 0 ? (m_net + inv / 2.0 - InpInventoryTargetBasePct / 100.0 * inv) / inv : 0;
     }
   void              NetOppositePositions(void)
     {
      ulong buy = 0, sell = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0 || PositionGetInteger(POSITION_MAGIC) != g_hb_magic || PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            buy = t;
         else
            sell = t;
        }
      if(buy > 0 && sell > 0)
         g_hb_trade.PositionCloseBy(buy, sell);
     }
   int               ActiveOrders(ulong &tickets[], double &buy_prices[], double &sell_prices[])
     {
      ArrayResize(tickets, 0);
      ArrayResize(buy_prices, 0);
      ArrayResize(sell_prices, 0);
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong t = OrderGetTicket(i);
         if(t == 0 || OrderGetInteger(ORDER_MAGIC) != g_hb_magic || OrderGetString(ORDER_SYMBOL) != m_symbol)
            continue;
         int n = ArraySize(tickets);
         ArrayResize(tickets, n + 1);
         tickets[n] = t;
         double p = OrderGetDouble(ORDER_PRICE_OPEN);
         ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         if(type == ORDER_TYPE_BUY_LIMIT)
           {
            int b = ArraySize(buy_prices);
            ArrayResize(buy_prices, b + 1);
            buy_prices[b] = p;
           }
         else
           {
            int s = ArraySize(sell_prices);
            ArrayResize(sell_prices, s + 1);
            sell_prices[s] = p;
           }
        }
      return ArraySize(tickets);
     }
   void              Track(const ulong t)
     {
      int n = ArraySize(m_tracked);
      ArrayResize(m_tracked, n + 1);
      m_tracked[n] = t;
     }
   // A fill delays the next quotes by filled_order_delay
   void              ProcessFills(void)
     {
      for(int i = ArraySize(m_tracked) - 1; i >= 0; i--)
        {
         if(HbOrderIsPending(m_tracked[i]))
            continue;
         double filled = HbHistoryFilledVolume(m_tracked[i]);
         if(filled < 0)
            continue;
         if(filled > 0)
           {
            m_create_ts = HbNow() + InpFilledOrderDelay;
            HbLog(StringFormat("order %I64u filled %.2f lots, next quotes in %ds", m_tracked[i], filled, InpFilledOrderDelay));
           }
         ArrayRemove(m_tracked, i, 1);
        }
     }
   void              CancelOnMaxAge(void)
     {
      datetime now = HbNow();
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong t = OrderGetTicket(i);
         if(t == 0 || OrderGetInteger(ORDER_MAGIC) != g_hb_magic || OrderGetString(ORDER_SYMBOL) != m_symbol)
            continue;
         if(now - (datetime)OrderGetInteger(ORDER_TIME_SETUP) > InpMaxOrderAge)
            g_hb_trade.OrderDelete(t);
        }
     }
   bool              CalculatePrices(void)
     {
      double price = HbMid(m_symbol);
      m_vol = Volatility();
      m_kappa = Kappa();
      double gamma = InpRiskFactor;
      if(InpInventoryLots <= 0 || gamma <= 0 || m_kappa <= 0 || m_vol <= 0)
         return false;
      double time_left_fraction = 1.0; // infinite timespan
      m_reservation = price - m_q * gamma * m_vol * time_left_fraction;
      m_optimal_spread = gamma * m_vol * time_left_fraction + 2.0 * MathLog(1.0 + gamma / m_kappa) / gamma;
      double min_spread = price / 100.0 * HbTune(InpMinSpread);
      m_optimal_ask = MathMax(m_reservation + m_optimal_spread / 2.0, price + min_spread / 2.0);
      m_optimal_bid = MathMin(m_reservation - m_optimal_spread / 2.0, price - min_spread / 2.0);
      return m_optimal_bid > 0 && m_optimal_ask > 0;
     }
   void              CreateProposal(void)
     {
      int levels = (int)MathMax(1, InpOrderLevels);
      double level_step = (m_optimal_spread / 2.0) / 100.0 * InpLevelDistances;
      double size = HbNormLots(m_symbol, InpOrderAmount, false);
      ArrayResize(m_buys, 0);
      ArrayResize(m_sells, 0);
      if(size <= 0)
         return;
      ArrayResize(m_buys, levels);
      ArrayResize(m_sells, levels);
      for(int i = 0; i < levels; i++)
        {
         m_buys[i].price = HbNormPrice(m_symbol, m_optimal_bid - i * level_step);
         m_buys[i].size = size;
         m_sells[i].price = HbNormPrice(m_symbol, m_optimal_ask + i * level_step);
         m_sells[i].size = size;
        }
      // eta: shrink orders that would push inventory further from the target
      if(InpOrderAmountShapeFactor != 0)
        {
         for(int i = 0; i < levels; i++)
           {
            if(m_q > 0)
               m_buys[i].size = HbNormLots(m_symbol, m_buys[i].size * MathExp(-InpOrderAmountShapeFactor * m_q), false);
            if(m_q < 0)
               m_sells[i].size = HbNormLots(m_symbol, m_sells[i].size * MathExp(InpOrderAmountShapeFactor * m_q), false);
           }
        }
      // budget: base balance (net + inv/2) caps sells, quote balance (inv - base) caps buys
      double base = m_net + InpInventoryLots / 2.0;
      double quote = InpInventoryLots - base;
      for(int i = 0; i < levels; i++)
        {
         double b = MathMin(m_buys[i].size, MathMax(0.0, quote));
         m_buys[i].size = HbNormLots(m_symbol, b, false);
         quote -= m_buys[i].size;
         double s = MathMin(m_sells[i].size, MathMax(0.0, base));
         m_sells[i].size = HbNormLots(m_symbol, s, false);
         base -= m_sells[i].size;
        }
     }
   bool              WithinTolerance(double &current[], const HbQuote &proposal[])
     {
      int n = ArraySize(current);
      int m = 0;
      double prop[];
      for(int i = 0; i < ArraySize(proposal); i++)
         if(proposal[i].size > 0)
           {
            ArrayResize(prop, m + 1);
            prop[m++] = proposal[i].price;
           }
      if(n != m)
         return false;
      ArraySort(current);
      ArraySort(prop);
      for(int i = 0; i < n; i++)
         if(current[i] == 0 || MathAbs(prop[i] - current[i]) / current[i] > InpOrderRefreshTolerancePct / 100.0)
            return false;
      return true;
     }
   void              SetTimers(void)
     {
      datetime now = HbNow();
      datetime next_cycle = now + InpOrderRefreshTime;
      if(m_create_ts <= now)
         m_create_ts = next_cycle;
      if(m_cancel_ts <= now)
         m_cancel_ts = m_create_ts < next_cycle ? m_create_ts : next_cycle;
     }

   virtual void      UpdateProcessedData(void)
     {
      PushSample(m_mid_samples, HbMid(m_symbol));
      PushSample(m_spread_samples, HbAsk(m_symbol) - HbBid(m_symbol));
     }
   virtual void      DetermineActions(void)
     {
      if(InpNetPositions)
         NetOppositePositions();
      ProcessFills();
      CancelOnMaxAge();
      ReadInventory();
      if(!IsReady())
         return;
      datetime now = HbNow();
      bool have_proposal = false;
      if(m_create_ts <= now && CalculatePrices())
        {
         CreateProposal();
         have_proposal = true;
        }
      ulong tickets[];
      double buy_prices[], sell_prices[];
      int active = ActiveOrders(tickets, buy_prices, sell_prices);
      if(m_cancel_ts <= now && active > 0)
        {
         if(have_proposal && WithinTolerance(buy_prices, m_buys) && WithinTolerance(sell_prices, m_sells))
            SetTimers();
         else
           {
            for(int i = 0; i < active; i++)
               g_hb_trade.OrderDelete(tickets[i]);
            active = ActiveOrders(tickets, buy_prices, sell_prices);
           }
        }
      if(have_proposal && m_create_ts < now && active == 0)
        {
         bool created = false;
         for(int i = 0; i < ArraySize(m_buys); i++)
            if(m_buys[i].size > 0)
              {
               ulong t = HbPlaceOpen(m_symbol, HB_BUY, HB_ORDER_LIMIT_MAKER, m_buys[i].size, m_buys[i].price, 0, 0, "HB AS");
               if(t > 0)
                 {
                  Track(t);
                  created = true;
                 }
              }
         for(int i = 0; i < ArraySize(m_sells); i++)
            if(m_sells[i].size > 0)
              {
               ulong t = HbPlaceOpen(m_symbol, HB_SELL, HB_ORDER_LIMIT_MAKER, m_sells[i].size, m_sells[i].price, 0, 0, "HB AS");
               if(t > 0)
                 {
                  Track(t);
                  created = true;
                 }
              }
         if(created)
            SetTimers();
        }
     }
   virtual string    StatusHeader(void)
     {
      int d = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      if(!IsReady())
         return StringFormat("collecting volatility samples %d/%d", ArraySize(m_mid_samples), InpVolatilityBufferSize);
      return StringFormat("net %.2f lots | q %.3f | vol %s | kappa %.2f\nreservation %s | optimal spread %s | bid %s | ask %s",
                          m_net, m_q, DoubleToString(m_vol, d + 2), m_kappa, DoubleToString(m_reservation, d),
                          DoubleToString(m_optimal_spread, d), DoubleToString(m_optimal_bid, d),
                          DoubleToString(m_optimal_ask, d));
     }

public:
                     CAvellanedaController(void)
     {
      m_create_ts = 0; m_cancel_ts = 0; m_net = 0; m_q = 0; m_vol = 0; m_kappa = 0;
      m_reservation = 0; m_optimal_spread = 0; m_optimal_bid = 0; m_optimal_ask = 0;
     }
   void              Reset(void)
     {
      ArrayResize(m_mid_samples, 0);
      ArrayResize(m_spread_samples, 0);
      ArrayResize(m_tracked, 0);
      m_create_ts = 0;
      m_cancel_ts = 0;
     }
  };

CAvellanedaController g_ctrl;

int OnInit()
  {
   g_hb_verbose = InpVerbose;
   HbInit("Avellaneda", InpMagic, InpDeviation);
   if(InpNetPositions && !HbIsHedgingAccount())
      Print("Netting account: positions already net, 'Close opposite positions' is not needed.");
   if(InpOrderAmount <= 0 || InpInventoryLots <= 0 || InpRiskFactor <= 0 || InpOrderRefreshTime < 1 ||
      InpVolatilityBufferSize < 2 || InpInventoryTargetBasePct < 0 || InpInventoryTargetBasePct > 100)
      return INIT_PARAMETERS_INCORRECT;
   HbAutoTune(_Symbol);
   g_ctrl.SetIdentity("avellaneda", _Symbol);
   g_ctrl.Reset();
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason) { HbFinishController(&g_ctrl, reason, InpCancelOnRemove); }
void OnTick()  { g_ctrl.Run(); }
void OnTimer() { g_ctrl.Run(); }

//+------------------------------------------------------------------+
//| Hummingbot MT5 - controllers                                     |
//| ControllerBase, DirectionalTradingControllerBase and             |
//| MarketMakingControllerBase from hummingbot/strategy_v2           |
//+------------------------------------------------------------------+
#ifndef HB_CONTROLLERS_MQH
#define HB_CONTROLLERS_MQH

#include "Core.mqh"
#include "Indicators.mqh"
#include "Executors.mqh"

//+------------------------------------------------------------------+
//| Base controller: owns executors, runs them once per second,      |
//| persists them so a restart picks up the same orders/positions    |
//+------------------------------------------------------------------+
class CHbController
  {
protected:
   CArrayObj          m_executors;
   string             m_symbol;
   string             m_name;
   string             m_state_file;
   datetime           m_last_run;
   datetime           m_last_save;
   bool               m_ready;

   virtual void       UpdateProcessedData(void) {}
   virtual void       DetermineActions(void) = 0;
   virtual string     StatusHeader(void) { return ""; }

   void               AddExecutor(CHbExecutor *e)
     {
      if(e == NULL)
         return;
      m_executors.Add(e);
      e.Process();
     }
   void               Prune(void)
     {
      datetime now = HbNow();
      for(int i = m_executors.Total() - 1; i >= 0; i--)
        {
         CHbExecutor *e = (CHbExecutor *)m_executors.At(i);
         if(e != NULL && !e.IsActive() && (now - e.CloseTimestamp() > 86400 || m_executors.Total() > 500))
            m_executors.Delete(i);
        }
     }
   void               ShowStatus(void)
     {
      if(HbIsTester() && !MQLInfoInteger(MQL_VISUAL_MODE))
         return;
      string s = StringFormat("Hummingbot %s | %s | magic %I64d\n", m_name, m_symbol, g_hb_magic);
      string header = StatusHeader();
      if(StringLen(header) > 0)
         s += header + "\n";
      int active = 0;
      double realized = 0, unrealized = 0;
      string lines = "";
      for(int i = 0; i < m_executors.Total(); i++)
        {
         CHbExecutor *e = (CHbExecutor *)m_executors.At(i);
         if(e == NULL)
            continue;
         realized += e.RealizedPnl();
         if(!e.IsActive())
            continue;
         active++;
         unrealized += e.UnrealizedPnl();
         if(active <= 12)
            lines += "  " + e.Describe() + "\n";
        }
      s += StringFormat("executors active=%d | unrealized %.2f | realized (24h) %.2f %s\n", active, unrealized, realized,
                        AccountInfoString(ACCOUNT_CURRENCY));
      Comment(s + lines);
     }

public:
                      CHbController(void)
     {
      m_executors.FreeMode(true);
      m_symbol = _Symbol;
      m_name = "controller";
      m_last_run = 0;
      m_last_save = 0;
      m_ready = true;
     }
   virtual           ~CHbController(void) { m_executors.Clear(); }

   void               SetIdentity(const string name, const string sym)
     {
      m_name = name;
      m_symbol = sym;
      m_state_file = StringFormat("Hummingbot\\%s_%s_%I64d.bin", name, sym, g_hb_magic);
     }
   int                Total(void) const { return m_executors.Total(); }
   CHbExecutor       *At(const int i) const { return (CHbExecutor *)m_executors.At(i); }

   // Hummingbot runs controllers on a 1 second clock
   void               Run(void)
     {
      datetime now = HbNow();
      if(now == m_last_run)
         return;
      m_last_run = now;
      if(!m_ready)
         return;
      UpdateProcessedData();
      DetermineActions();
      for(int i = 0; i < m_executors.Total(); i++)
        {
         CHbExecutor *e = (CHbExecutor *)m_executors.At(i);
         if(e != NULL && e.IsActive())
            e.Process();
        }
      Prune();
      if(now - m_last_save >= 5)
         Save();
      ShowStatus();
     }

   int                CountActive(const int side = 0, const string level_id = "")
     {
      int n = 0;
      for(int i = 0; i < m_executors.Total(); i++)
        {
         CHbExecutor *e = (CHbExecutor *)m_executors.At(i);
         if(e == NULL || !e.IsActive())
            continue;
         if(side != 0 && (int)e.Side() != side)
            continue;
         if(level_id != "" && e.LevelId() != level_id)
            continue;
         n++;
        }
      return n;
     }

   void               StopAll(const bool keep_position)
     {
      for(int i = 0; i < m_executors.Total(); i++)
        {
         CHbExecutor *e = (CHbExecutor *)m_executors.At(i);
         if(e != NULL && e.IsActive())
           {
            e.EarlyStop(keep_position);
            e.Process();
           }
        }
     }

   // Cancels every resting order of this EA (positions keep their server-side SL/TP)
   void               CancelPendingOrders(void)
     {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong t = OrderGetTicket(i);
         if(t == 0)
            continue;
         if(OrderGetInteger(ORDER_MAGIC) == g_hb_magic)
            g_hb_trade.OrderDelete(t);
        }
     }

   void               Save(void)
     {
      m_last_save = HbNow();
      if(HbIsTester())
         return;
      int h = FileOpen(m_state_file, FILE_WRITE | FILE_BIN);
      if(h == INVALID_HANDLE)
         return;
      FileWriteInteger(h, HB_STATE_VERSION);
      int n = 0;
      for(int i = 0; i < m_executors.Total(); i++)
        {
         CHbExecutor *e = (CHbExecutor *)m_executors.At(i);
         if(e != NULL && e.IsActive())
            n++;
        }
      FileWriteInteger(h, n);
      for(int i = 0; i < m_executors.Total(); i++)
        {
         CHbExecutor *e = (CHbExecutor *)m_executors.At(i);
         if(e == NULL || !e.IsActive())
            continue;
         FileWriteInteger(h, e.ExecType());
         e.Save(h);
        }
      SaveExtra(h);
      FileClose(h);
     }
   virtual void       SaveExtra(const int h) {}
   virtual void       LoadExtra(const int h) {}

   void               Load(void)
     {
      if(HbIsTester() || !FileIsExist(m_state_file))
         return;
      int h = FileOpen(m_state_file, FILE_READ | FILE_BIN);
      if(h == INVALID_HANDLE)
         return;
      // OnInit can run again without the EA being unloaded (timeframe or input change): drop the in-memory copy
      m_executors.Clear();
      if(FileReadInteger(h) != HB_STATE_VERSION)
        {
         FileClose(h);
         HbLog("state file version changed, starting fresh");
         return;
        }
      int n = FileReadInteger(h);
      int loaded = 0;
      for(int i = 0; i < n && i < 1000; i++)
        {
         CHbExecutor *e = HbNewExecutor(FileReadInteger(h));
         if(e == NULL)
            break;
         if(!e.Load(h))
           {
            delete e;
            break;
           }
         m_executors.Add(e);
         loaded++;
        }
      if(loaded == n)
         LoadExtra(h);
      FileClose(h);
      HbLog(StringFormat("restored %d executor(s) from %s", loaded, m_state_file));
     }
  };

//+------------------------------------------------------------------+
//| Directional trading: a signal (-1/0/1) opens executors on the    |
//| signal side, limited per side and by a cooldown                  |
//+------------------------------------------------------------------+
class CHbDirectionalController : public CHbController
  {
protected:
   double             m_total_lots;
   int                m_max_executors_per_side;
   int                m_cooldown_time;
   HbTripleBarrier    m_tb;
   int                m_signal;
   string             m_signal_info;

   virtual CHbExecutor *CreateExecutor(const ENUM_HB_SIDE side, const double price, const double lots)
     {
      CHbPositionExecutor *e = new CHbPositionExecutor();
      e.Setup(m_symbol, side, price, lots, m_tb, m_name);
      return e;
     }
   bool               CanCreateExecutor(const int signal)
     {
      int active = 0;
      datetime max_ts = 0;
      for(int i = 0; i < m_executors.Total(); i++)
        {
         CHbExecutor *e = (CHbExecutor *)m_executors.At(i);
         if(e == NULL || !e.IsActive() || (int)e.Side() != (signal > 0 ? 1 : -1))
            continue;
         active++;
         if(e.Timestamp() > max_ts)
            max_ts = e.Timestamp();
        }
      return active < m_max_executors_per_side && HbNow() - max_ts > m_cooldown_time;
     }
   virtual void       DetermineActions(void)
     {
      if(m_signal == 0 || !CanCreateExecutor(m_signal))
         return;
      double price = HbMid(m_symbol);
      double lots = m_total_lots / m_max_executors_per_side;
      ENUM_HB_SIDE side = m_signal > 0 ? HB_BUY : HB_SELL;
      HbLog(StringFormat("signal %d -> new %s executor %.2f lots @ %s", m_signal, HbSideName(side), lots,
                         DoubleToString(price, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS))));
      AddExecutor(CreateExecutor(side, price, lots));
     }
   virtual string     StatusHeader(void)
     {
      return StringFormat("signal %d %s | max/side %d | cooldown %ds", m_signal, m_signal_info,
                          m_max_executors_per_side, m_cooldown_time);
     }

public:
                      CHbDirectionalController(void)
     {
      m_total_lots = 0.1;
      m_max_executors_per_side = 2;
      m_cooldown_time = 300;
      m_tb.Init();
      m_signal = 0;
      m_signal_info = "";
     }
   void               ConfigureDirectional(const double total_lots, const int max_per_side, const int cooldown,
                                           const double stop_loss, const double take_profit, const int time_limit,
                                           const ENUM_HB_ORDER_TYPE tp_order_type, const double trailing_activation,
                                           const double trailing_delta)
     {
      m_total_lots = total_lots;
      m_max_executors_per_side = (int)MathMax(1, max_per_side);
      m_cooldown_time = cooldown;
      m_tb.stop_loss = stop_loss;
      m_tb.take_profit = take_profit;
      m_tb.time_limit = time_limit;
      m_tb.trailing_activation = trailing_activation;
      m_tb.trailing_delta = trailing_delta;
      m_tb.open_order_type = HB_ORDER_MARKET;   // taker controller
      m_tb.take_profit_order_type = tp_order_type;
     }
  };

//+------------------------------------------------------------------+
//| Market making: one executor per level ("buy_0", "sell_1", ...)   |
//| priced around a reference price, refreshed while unfilled        |
//+------------------------------------------------------------------+
class CHbMarketMakingController : public CHbController
  {
protected:
   double             m_buy_spreads[];
   double             m_sell_spreads[];
   double             m_buy_amounts[];
   double             m_sell_amounts[];
   double             m_total_lots;
   int                m_refresh_time;
   int                m_cooldown_time;
   HbTripleBarrier    m_tb;
   double             m_reference_price;
   double             m_spread_multiplier;

   virtual void       UpdateProcessedData(void)
     {
      m_reference_price = HbMid(m_symbol);
      m_spread_multiplier = 1.0;
     }
   virtual CHbExecutor *CreateExecutor(const string level_id, const ENUM_HB_SIDE side, const double price,
                                       const double lots)
     {
      CHbPositionExecutor *e = new CHbPositionExecutor();
      e.Setup(m_symbol, side, price, lots, m_tb, level_id);
      return e;
     }
   virtual bool       RefreshCondition(CHbExecutor *e)
     {
      return !e.IsTrading() && HbNow() - e.Timestamp() > m_refresh_time;
     }
   // A level is busy while its executor runs, and for `cooldown` seconds after a stop loss
   bool               LevelIsWorking(const string level_id)
     {
      datetime now = HbNow();
      for(int i = 0; i < m_executors.Total(); i++)
        {
         CHbExecutor *e = (CHbExecutor *)m_executors.At(i);
         if(e == NULL || e.LevelId() != level_id)
            continue;
         if(e.IsActive())
            return true;
         if(e.CloseType() == HB_CLOSE_STOP_LOSS && now - e.CloseTimestamp() < m_cooldown_time)
            return true;
        }
      return false;
     }
   void               LevelPriceAndLots(const ENUM_HB_SIDE side, const int level, double &price, double &lots)
     {
      double total_pct = 0;
      for(int i = 0; i < ArraySize(m_buy_amounts); i++)
         total_pct += m_buy_amounts[i];
      for(int i = 0; i < ArraySize(m_sell_amounts); i++)
         total_pct += m_sell_amounts[i];
      double pct = side == HB_BUY ? m_buy_amounts[level] : m_sell_amounts[level];
      double spread = (side == HB_BUY ? m_buy_spreads[level] : m_sell_spreads[level]) * m_spread_multiplier;
      price = m_reference_price * (1.0 + (side == HB_BUY ? -1.0 : 1.0) * spread);
      lots = total_pct > 0 ? m_total_lots * pct / total_pct : 0;
     }
   virtual void       DetermineActions(void)
     {
      if(m_reference_price <= 0)
         return;
      for(int s = 0; s < 2; s++)
        {
         ENUM_HB_SIDE side = s == 0 ? HB_BUY : HB_SELL;
         int levels = side == HB_BUY ? ArraySize(m_buy_spreads) : ArraySize(m_sell_spreads);
         for(int level = 0; level < levels; level++)
           {
            string level_id = (side == HB_BUY ? "buy_" : "sell_") + IntegerToString(level);
            if(LevelIsWorking(level_id))
               continue;
            double price, lots;
            LevelPriceAndLots(side, level, price, lots);
            if(lots <= 0 || price <= 0)
               continue;
            AddExecutor(CreateExecutor(level_id, side, price, lots));
           }
        }
      for(int i = 0; i < m_executors.Total(); i++)
        {
         CHbExecutor *e = (CHbExecutor *)m_executors.At(i);
         if(e != NULL && e.Status() == HB_RUNNING && RefreshCondition(e))
            e.EarlyStop(false);
        }
     }
   virtual string     StatusHeader(void)
     {
      return StringFormat("reference %s | spread multiplier %.5f | refresh %ds",
                          DoubleToString(m_reference_price, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS)),
                          m_spread_multiplier, m_refresh_time);
     }

public:
                      CHbMarketMakingController(void)
     {
      m_total_lots = 0.1;
      m_refresh_time = 300;
      m_cooldown_time = 15;
      m_tb.Init();
      m_reference_price = 0;
      m_spread_multiplier = 1;
     }
   // Spreads/amounts are comma-separated lists; empty amounts mean equal weights (Hummingbot default)
   bool               ConfigureMarketMaking(const string buy_spreads, const string sell_spreads,
                                            const string buy_amounts, const string sell_amounts,
                                            const double total_lots, const int refresh_time, const int cooldown,
                                            const double stop_loss, const double take_profit, const int time_limit,
                                            const ENUM_HB_ORDER_TYPE tp_order_type, const double trailing_activation,
                                            const double trailing_delta)
     {
      HbParseList(buy_spreads, m_buy_spreads);
      HbParseList(sell_spreads, m_sell_spreads);
      if(HbParseList(buy_amounts, m_buy_amounts) == 0)
        {
         ArrayResize(m_buy_amounts, ArraySize(m_buy_spreads));
         ArrayInitialize(m_buy_amounts, 1.0);
        }
      if(HbParseList(sell_amounts, m_sell_amounts) == 0)
        {
         ArrayResize(m_sell_amounts, ArraySize(m_sell_spreads));
         ArrayInitialize(m_sell_amounts, 1.0);
        }
      if(ArraySize(m_buy_amounts) != ArraySize(m_buy_spreads) || ArraySize(m_sell_amounts) != ArraySize(m_sell_spreads))
        {
         Print("The number of amounts must match the number of spreads");
         return false;
        }
      m_total_lots = total_lots;
      m_refresh_time = refresh_time;
      m_cooldown_time = cooldown;
      m_tb.stop_loss = stop_loss;
      m_tb.take_profit = take_profit;
      m_tb.time_limit = time_limit;
      m_tb.trailing_activation = trailing_activation;
      m_tb.trailing_delta = trailing_delta;
      m_tb.open_order_type = HB_ORDER_LIMIT;    // maker controller
      m_tb.take_profit_order_type = tp_order_type;
      return true;
     }
  };

//+------------------------------------------------------------------+
//| EA lifecycle helpers                                             |
//+------------------------------------------------------------------+
bool HbCheckAccount(void)
  {
   if(!HbIsHedgingAccount())
     {
      Alert("Hummingbot EAs run one position per executor and need a HEDGING account. "
            "Open a hedging account (most brokers offer it) or switch the account type.");
      return false;
     }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && !HbIsTester())
      Print("Algo trading is disabled in the terminal: enable 'Algo Trading' to let the EA place orders.");
   return true;
  }

void HbFinishController(CHbController *ctrl, const int reason, const bool cancel_on_remove)
  {
   EventKillTimer();
   if(ctrl == NULL)
      return;
   if(reason == REASON_REMOVE && cancel_on_remove)
     {
      ctrl.CancelPendingOrders();
      HbLog("EA removed: pending orders cancelled, open positions keep their server-side SL/TP");
     }
   ctrl.Save();
   Comment("");
  }

#endif

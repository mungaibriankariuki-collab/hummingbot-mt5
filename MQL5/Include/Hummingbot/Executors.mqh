//+------------------------------------------------------------------+
//| Hummingbot MT5 - executors                                       |
//| PositionExecutor, DCAExecutor and GridExecutor from              |
//| hummingbot/strategy_v2/executors, on an MT5 hedging account.     |
//| Order ticket == position identifier links orders to positions.   |
//+------------------------------------------------------------------+
#ifndef HB_EXECUTORS_MQH
#define HB_EXECUTORS_MQH

#include "Core.mqh"

//+------------------------------------------------------------------+
//| Base executor                                                    |
//+------------------------------------------------------------------+
class CHbExecutor : public CObject
  {
protected:
   string             m_id;
   string             m_symbol;
   ENUM_HB_SIDE       m_side;
   datetime           m_timestamp;
   string             m_level_id;
   ENUM_HB_STATUS     m_status;
   ENUM_HB_CLOSE_TYPE m_close_type;
   datetime           m_close_timestamp;
   double             m_realized_pnl;
   bool               m_keep_position;

   void               Terminate(const ENUM_HB_CLOSE_TYPE close_type)
     {
      m_close_type = close_type;
      m_status = HB_TERMINATED;
      m_close_timestamp = HbNow();
      HbLog(StringFormat("executor %s %s %s closed: %s pnl=%.2f", m_id, m_level_id, HbSideName(m_side),
                         HbCloseTypeName(m_close_type), m_realized_pnl));
     }
   void               BeginShutdown(const ENUM_HB_CLOSE_TYPE close_type, const bool keep_position)
     {
      if(m_status != HB_RUNNING)
         return;
      m_close_type = close_type;
      m_keep_position = keep_position;
      m_status = HB_SHUTTING_DOWN;
      m_close_timestamp = HbNow();
     }
   string             TradeComment(void) const
     {
      string c = "HB " + m_level_id;
      return StringSubstr(c, 0, 26);
     }

public:
                      CHbExecutor(void)
     {
      m_id = HbNewId();
      m_symbol = _Symbol;
      m_side = HB_BUY;
      m_timestamp = HbNow();
      m_level_id = "";
      m_status = HB_RUNNING;
      m_close_type = HB_CLOSE_NONE;
      m_close_timestamp = 0;
      m_realized_pnl = 0;
      m_keep_position = false;
     }
   virtual int        ExecType(void) const = 0;
   virtual void       Process(void) = 0;
   virtual bool       IsTrading(void) = 0;
   virtual double     FilledLots(void) = 0;
   virtual double     NetPnlPct(void) = 0;
   virtual double     UnrealizedPnl(void) = 0;
   // Appends the identifiers of positions this executor currently manages
   virtual void       PositionIds(ulong &ids[]) = 0;
   virtual void       EarlyStop(const bool keep_position)
     {
      BeginShutdown(keep_position ? HB_CLOSE_POSITION_HOLD : HB_CLOSE_EARLY_STOP, keep_position);
     }

   bool               IsActive(void) const { return m_status != HB_TERMINATED; }
   string             Id(void) const { return m_id; }
   string             Sym(void) const { return m_symbol; }
   ENUM_HB_SIDE       Side(void) const { return m_side; }
   datetime           Timestamp(void) const { return m_timestamp; }
   string             LevelId(void) const { return m_level_id; }
   ENUM_HB_STATUS     Status(void) const { return m_status; }
   ENUM_HB_CLOSE_TYPE CloseType(void) const { return m_close_type; }
   datetime           CloseTimestamp(void) const { return m_close_timestamp; }
   double             RealizedPnl(void) const { return m_realized_pnl; }

   virtual void       Save(const int h)
     {
      HbWriteString(h, m_id);
      HbWriteString(h, m_symbol);
      FileWriteInteger(h, (int)m_side);
      FileWriteLong(h, (long)m_timestamp);
      HbWriteString(h, m_level_id);
      FileWriteInteger(h, (int)m_status);
      FileWriteInteger(h, (int)m_close_type);
      FileWriteLong(h, (long)m_close_timestamp);
      FileWriteDouble(h, m_realized_pnl);
      FileWriteInteger(h, m_keep_position ? 1 : 0);
     }
   virtual bool       Load(const int h)
     {
      m_id = HbReadString(h);
      m_symbol = HbReadString(h);
      m_side = (ENUM_HB_SIDE)FileReadInteger(h);
      m_timestamp = (datetime)FileReadLong(h);
      m_level_id = HbReadString(h);
      m_status = (ENUM_HB_STATUS)FileReadInteger(h);
      m_close_type = (ENUM_HB_CLOSE_TYPE)FileReadInteger(h);
      m_close_timestamp = (datetime)FileReadLong(h);
      m_realized_pnl = FileReadDouble(h);
      m_keep_position = FileReadInteger(h) != 0;
      return StringLen(m_id) > 0 && StringLen(m_symbol) > 0;
     }
   virtual string     Describe(void)
     {
      return StringFormat("%s %s %s lots=%.2f pnl=%.3f%%", m_level_id, HbSideName(m_side),
                          IsTrading() ? "trading" : "placed", FilledLots(), NetPnlPct() * 100.0);
     }
  };

//+------------------------------------------------------------------+
//| PositionExecutor: one entry order + triple barrier               |
//+------------------------------------------------------------------+
class CHbPositionExecutor : public CHbExecutor
  {
protected:
   double             m_entry_price;
   double             m_lots;
   HbTripleBarrier    m_tb;
   ulong              m_order;
   bool               m_trailing_on;
   double             m_trailing_trigger;
   int                m_missing;
   datetime           m_last_stops;
   // live values refreshed by Process()
   double             m_fill_price;
   double             m_filled;
   double             m_pnl_pct;
   double             m_upnl;

   bool               IsExpired(void) const
     {
      return m_tb.time_limit > 0 && HbNow() >= m_timestamp + m_tb.time_limit;
     }
   void               DesiredStops(const double entry, double &sl, double &tp) const
     {
      int s = (int)m_side;
      sl = m_tb.stop_loss > 0 ? entry * (1.0 - s * m_tb.stop_loss) : 0.0;
      if(m_trailing_on)
        {
         double tsl = entry * (1.0 + s * m_trailing_trigger);
         if(sl == 0 || (m_side == HB_BUY && tsl > sl) || (m_side == HB_SELL && tsl < sl))
            sl = tsl;
        }
      tp = m_tb.take_profit > 0 ? entry * (1.0 + s * m_tb.take_profit) : 0.0;
     }
   void               Finish(void)
     {
      ENUM_HB_CLOSE_TYPE ct = m_close_type;
      double profit, price;
      ENUM_DEAL_REASON reason;
      if(HbClosedPositionResult(m_order, profit, price, reason))
        {
         m_realized_pnl = profit;
         if(m_status == HB_RUNNING)
           {
            if(reason == DEAL_REASON_TP)
               ct = HB_CLOSE_TAKE_PROFIT;
            else
               if(reason == DEAL_REASON_SL || reason == DEAL_REASON_SO)
                  ct = m_trailing_on ? HB_CLOSE_TRAILING_STOP : HB_CLOSE_STOP_LOSS;
               else
                  ct = HB_CLOSE_EARLY_STOP;
           }
        }
      Terminate(ct == HB_CLOSE_NONE ? HB_CLOSE_EARLY_STOP : ct);
     }
   void               Shutdown(void)
     {
      if(HbOrderIsPending(m_order))
         HbCancelOrder(m_order);
      ulong pos = HbFindPosition(m_order);
      if(pos > 0 && !m_keep_position)
         HbClosePositionByTicket(pos);
      // a held position loses its take profit order, as in Hummingbot; the stop loss stays as protection
      if(pos > 0 && m_keep_position && PositionSelectByTicket(pos) && PositionGetDouble(POSITION_TP) > 0)
         g_hb_trade.PositionModify(pos, PositionGetDouble(POSITION_SL), 0);
      if(!HbOrderIsPending(m_order) && (m_keep_position || HbFindPosition(m_order) == 0))
         Finish();
     }

public:
                      CHbPositionExecutor(void)
     {
      m_entry_price = 0; m_lots = 0; m_order = 0;
      m_tb.Init();
      m_trailing_on = false; m_trailing_trigger = 0;
      m_missing = 0; m_last_stops = 0;
      m_fill_price = 0; m_filled = 0; m_pnl_pct = 0; m_upnl = 0;
     }
   void               Setup(const string sym, const ENUM_HB_SIDE side, const double entry_price, const double lots,
                            const HbTripleBarrier &tb, const string level_id)
     {
      m_symbol = sym;
      m_side = side;
      m_entry_price = entry_price;
      m_lots = lots;
      m_tb = tb;
      m_level_id = level_id;
     }
   virtual int        ExecType(void) const { return HB_EXEC_POSITION; }
   double             EntryPrice(void) const { return m_entry_price; }
   ulong              OrderTicket(void) const { return m_order; }
   virtual bool       IsTrading(void) { return m_filled > 0; }
   virtual double     FilledLots(void) { return m_filled; }
   virtual double     NetPnlPct(void) { return m_pnl_pct; }
   virtual double     UnrealizedPnl(void) { return m_upnl; }
   // filled notional in account currency
   double             FilledNotional(void) { return m_filled * HbLotNotional(m_symbol, m_fill_price); }
   virtual void       PositionIds(ulong &ids[])
     {
      if(m_status != HB_TERMINATED && m_order > 0 && HbFindPosition(m_order) > 0)
        {
         int n = ArraySize(ids);
         ArrayResize(ids, n + 1);
         ids[n] = m_order;
        }
     }

   virtual void       Process(void)
     {
      if(m_status == HB_TERMINATED)
         return;
      if(m_order == 0)
        {
         if(m_status == HB_SHUTTING_DOWN)
           {
            Terminate(m_close_type);
            return;
           }
         double sl, tp;
         DesiredStops(m_entry_price, sl, tp);
         m_order = HbPlaceOpen(m_symbol, m_side, m_tb.open_order_type, m_lots, m_entry_price, sl, tp, TradeComment());
         if(m_order == 0)
            Terminate(HB_CLOSE_FAILED);
         return;
        }
      ulong pos = HbFindPosition(m_order);
      bool pending = HbOrderIsPending(m_order);
      m_filled = 0; m_upnl = 0;
      if(pos > 0 && PositionSelectByTicket(pos))
        {
         m_fill_price = PositionGetDouble(POSITION_PRICE_OPEN);
         m_filled = PositionGetDouble(POSITION_VOLUME);
         m_upnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        }
      if(m_status == HB_SHUTTING_DOWN)
        {
         Shutdown();
         return;
        }
      if(pos == 0)
        {
         m_pnl_pct = 0;
         if(pending)
           {
            if(IsExpired())
              {
               BeginShutdown(HB_CLOSE_TIME_LIMIT, false);
               Shutdown();
              }
            return;
           }
         double filled = HbHistoryFilledVolume(m_order);
         if(filled < 0)
           {
            // history not synchronised yet
            if(++m_missing > 30)
               Terminate(HB_CLOSE_FAILED);
            return;
           }
         if(filled > 0)
            Finish();          // closed on the server (SL/TP) or by hand
         else
            Terminate(HB_CLOSE_EARLY_STOP); // pending order cancelled outside the EA
         return;
        }
      // Position open: control the barriers (stop loss, trailing stop, take profit, time limit)
      double bid = HbBid(m_symbol), ask = HbAsk(m_symbol);
      m_pnl_pct = HbPnlPct(m_side, m_fill_price, bid, ask);
      ENUM_HB_CLOSE_TYPE trigger = HB_CLOSE_NONE;
      if(m_tb.stop_loss > 0 && m_pnl_pct <= -m_tb.stop_loss)
         trigger = HB_CLOSE_STOP_LOSS;
      if(trigger == HB_CLOSE_NONE && m_tb.HasTrailing())
        {
         if(!m_trailing_on)
           {
            if(m_pnl_pct > m_tb.trailing_activation)
              {
               m_trailing_on = true;
               m_trailing_trigger = m_pnl_pct - m_tb.trailing_delta;
              }
           }
         else
           {
            if(m_pnl_pct < m_trailing_trigger)
               trigger = HB_CLOSE_TRAILING_STOP;
            else
               if(m_pnl_pct - m_tb.trailing_delta > m_trailing_trigger)
                  m_trailing_trigger = m_pnl_pct - m_tb.trailing_delta;
           }
        }
      if(trigger == HB_CLOSE_NONE && m_tb.take_profit > 0 && m_pnl_pct >= m_tb.take_profit)
         trigger = HB_CLOSE_TAKE_PROFIT;
      if(trigger == HB_CLOSE_NONE && IsExpired())
         trigger = HB_CLOSE_TIME_LIMIT;
      if(trigger != HB_CLOSE_NONE)
        {
         BeginShutdown(trigger, false);
         Shutdown();
         return;
        }
      // keep the server-side protection in line with the barriers
      if(HbNow() - m_last_stops >= 5)
        {
         m_last_stops = HbNow();
         double sl, tp;
         DesiredStops(m_fill_price, sl, tp);
         HbEnsureStops(pos, m_symbol, m_side, sl, tp);
        }
     }

   virtual void       Save(const int h)
     {
      CHbExecutor::Save(h);
      FileWriteDouble(h, m_entry_price);
      FileWriteDouble(h, m_lots);
      HbWriteBarrier(h, m_tb);
      FileWriteLong(h, (long)m_order);
      FileWriteInteger(h, m_trailing_on ? 1 : 0);
      FileWriteDouble(h, m_trailing_trigger);
     }
   virtual bool       Load(const int h)
     {
      if(!CHbExecutor::Load(h))
         return false;
      m_entry_price = FileReadDouble(h);
      m_lots = FileReadDouble(h);
      HbReadBarrier(h, m_tb);
      m_order = (ulong)FileReadLong(h);
      m_trailing_on = FileReadInteger(h) != 0;
      m_trailing_trigger = FileReadDouble(h);
      return true;
     }
  };

//+------------------------------------------------------------------+
//| DCAExecutor (MAKER mode): a ladder of limit orders managed as    |
//| one position against its average entry price                     |
//+------------------------------------------------------------------+
class CHbDCAExecutor : public CHbExecutor
  {
protected:
   double             m_prices[];
   double             m_lots[];
   ulong              m_orders[];
   double             m_take_profit;
   double             m_stop_loss;
   double             m_trailing_activation;
   double             m_trailing_delta;
   int                m_time_limit;
   double             m_activation_bound;
   bool               m_trailing_on;
   double             m_trailing_trigger;
   int                m_failures;
   // live values
   double             m_filled;
   double             m_avg_price;
   double             m_pnl_pct;
   double             m_upnl;
   int                m_pending;
   int                m_placed;

   bool               IsExpired(void) const
     {
      return m_time_limit > 0 && HbNow() >= m_timestamp + m_time_limit;
     }
   bool               WithinActivationBounds(const double order_price, const double close_price) const
     {
      if(m_activation_bound <= 0)
         return true;
      if(m_side == HB_BUY)
         return order_price > close_price * (1.0 - m_activation_bound);
      return order_price < close_price * (1.0 + m_activation_bound);
     }
   void               Aggregate(void)
     {
      m_filled = 0; m_avg_price = 0; m_upnl = 0; m_pending = 0; m_placed = 0;
      double notional = 0;
      int n = ArraySize(m_orders);
      for(int i = 0; i < n; i++)
        {
         if(m_orders[i] == 0)
            continue;
         m_placed++;
         if(HbOrderIsPending(m_orders[i]))
            m_pending++;
         ulong pos = HbFindPosition(m_orders[i]);
         if(pos > 0 && PositionSelectByTicket(pos))
           {
            double v = PositionGetDouble(POSITION_VOLUME);
            m_filled += v;
            notional += v * PositionGetDouble(POSITION_PRICE_OPEN);
            m_upnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
           }
        }
      if(m_filled > 0)
         m_avg_price = notional / m_filled;
      m_pnl_pct = m_filled > 0 ? HbPnlPct(m_side, m_avg_price, HbBid(m_symbol), HbAsk(m_symbol)) : 0.0;
     }
   bool               AnyHistoryFill(void)
     {
      for(int i = 0; i < ArraySize(m_orders); i++)
         if(m_orders[i] != 0 && HbHistoryFilledVolume(m_orders[i]) > 0)
            return true;
      return false;
     }
   void               Finish(void)
     {
      m_realized_pnl = 0;
      for(int i = 0; i < ArraySize(m_orders); i++)
        {
         double profit, price;
         ENUM_DEAL_REASON reason;
         if(m_orders[i] != 0 && HbClosedPositionResult(m_orders[i], profit, price, reason))
            m_realized_pnl += profit;
        }
      Terminate(m_close_type == HB_CLOSE_NONE ? HB_CLOSE_EARLY_STOP : m_close_type);
     }
   void               Shutdown(void)
     {
      bool busy = false;
      for(int i = 0; i < ArraySize(m_orders); i++)
        {
         if(m_orders[i] == 0)
            continue;
         if(HbOrderIsPending(m_orders[i]))
           {
            HbCancelOrder(m_orders[i]);
            busy = true;
           }
         ulong pos = HbFindPosition(m_orders[i]);
         if(pos > 0 && !m_keep_position)
           {
            HbClosePositionByTicket(pos);
            busy = true;
           }
        }
      if(!busy)
         Finish();
     }

public:
                      CHbDCAExecutor(void)
     {
      m_take_profit = 0; m_stop_loss = 0; m_trailing_activation = 0; m_trailing_delta = 0;
      m_time_limit = 0; m_activation_bound = 0; m_trailing_on = false; m_trailing_trigger = 0;
      m_failures = 0; m_filled = 0; m_avg_price = 0; m_pnl_pct = 0; m_upnl = 0; m_pending = 0; m_placed = 0;
     }
   void               Setup(const string sym, const ENUM_HB_SIDE side, const double &prices[], const double &lots[],
                            const double take_profit, const double stop_loss, const double trailing_activation,
                            const double trailing_delta, const int time_limit, const double activation_bound,
                            const string level_id)
     {
      m_symbol = sym;
      m_side = side;
      ArrayCopy(m_prices, prices);
      ArrayCopy(m_lots, lots);
      int n = ArraySize(m_prices);
      ArrayResize(m_orders, n);
      for(int i = 0; i < n; i++)
         m_orders[i] = 0;
      m_take_profit = take_profit;
      m_stop_loss = stop_loss;
      m_trailing_activation = trailing_activation;
      m_trailing_delta = trailing_delta;
      m_time_limit = time_limit;
      m_activation_bound = activation_bound;
      m_level_id = level_id;
     }
   virtual int        ExecType(void) const { return HB_EXEC_DCA; }
   virtual bool       IsTrading(void) { return m_filled > 0; }
   virtual double     FilledLots(void) { return m_filled; }
   virtual double     NetPnlPct(void) { return m_pnl_pct; }
   virtual double     UnrealizedPnl(void) { return m_upnl; }
   virtual void       PositionIds(ulong &ids[])
     {
      if(m_status == HB_TERMINATED)
         return;
      for(int i = 0; i < ArraySize(m_orders); i++)
         if(m_orders[i] != 0 && HbFindPosition(m_orders[i]) > 0)
           {
            int n = ArraySize(ids);
            ArrayResize(ids, n + 1);
            ids[n] = m_orders[i];
           }
     }

   virtual void       Process(void)
     {
      if(m_status == HB_TERMINATED)
         return;
      Aggregate();
      if(m_status == HB_SHUTTING_DOWN)
        {
         Shutdown();
         return;
        }
      int n = ArraySize(m_prices);
      // open the next level of the ladder
      int next = -1;
      for(int i = 0; i < n; i++)
         if(m_orders[i] == 0)
           {
            next = i;
            break;
           }
      if(next >= 0 && !IsExpired() && WithinActivationBounds(m_prices[next], HbMid(m_symbol)))
        {
         ulong t = HbPlaceOpen(m_symbol, m_side, HB_ORDER_LIMIT, m_lots[next], m_prices[next], 0, 0, TradeComment());
         if(t > 0)
            m_orders[next] = t;
         else
            if(++m_failures >= 10)
              {
               BeginShutdown(HB_CLOSE_FAILED, false);
               return;
              }
        }
      bool all_executed = m_placed == n && m_pending == 0;
      ENUM_HB_CLOSE_TYPE trigger = HB_CLOSE_NONE;
      if(m_stop_loss > 0 && all_executed && m_filled > 0 && m_pnl_pct <= -m_stop_loss)
         trigger = HB_CLOSE_STOP_LOSS;
      if(trigger == HB_CLOSE_NONE && m_trailing_activation > 0 && m_trailing_delta > 0 && m_filled > 0)
        {
         if(!m_trailing_on)
           {
            if(m_pnl_pct > m_trailing_activation)
              {
               m_trailing_on = true;
               m_trailing_trigger = m_pnl_pct - m_trailing_delta;
              }
           }
         else
           {
            if(m_pnl_pct < m_trailing_trigger)
               trigger = HB_CLOSE_TRAILING_STOP;
            else
               if(m_pnl_pct - m_trailing_delta > m_trailing_trigger)
                  m_trailing_trigger = m_pnl_pct - m_trailing_delta;
           }
        }
      if(trigger == HB_CLOSE_NONE && m_take_profit > 0 && m_filled > 0 && m_pnl_pct > m_take_profit)
         trigger = HB_CLOSE_TAKE_PROFIT;
      if(trigger == HB_CLOSE_NONE && IsExpired())
         trigger = HB_CLOSE_TIME_LIMIT;
      if(trigger == HB_CLOSE_NONE && all_executed && m_filled == 0)
        {
         // every order is gone and nothing is open: closed or cancelled outside the EA
         m_close_type = AnyHistoryFill() ? HB_CLOSE_COMPLETED : HB_CLOSE_EARLY_STOP;
         Finish();
         return;
        }
      if(trigger != HB_CLOSE_NONE)
        {
         BeginShutdown(trigger, false);
         Shutdown();
        }
     }

   virtual void       Save(const int h)
     {
      CHbExecutor::Save(h);
      HbWriteDoubles(h, m_prices);
      HbWriteDoubles(h, m_lots);
      HbWriteTickets(h, m_orders);
      FileWriteDouble(h, m_take_profit);
      FileWriteDouble(h, m_stop_loss);
      FileWriteDouble(h, m_trailing_activation);
      FileWriteDouble(h, m_trailing_delta);
      FileWriteInteger(h, m_time_limit);
      FileWriteDouble(h, m_activation_bound);
      FileWriteInteger(h, m_trailing_on ? 1 : 0);
      FileWriteDouble(h, m_trailing_trigger);
     }
   virtual bool       Load(const int h)
     {
      if(!CHbExecutor::Load(h))
         return false;
      HbReadDoubles(h, m_prices);
      HbReadDoubles(h, m_lots);
      HbReadTickets(h, m_orders);
      m_take_profit = FileReadDouble(h);
      m_stop_loss = FileReadDouble(h);
      m_trailing_activation = FileReadDouble(h);
      m_trailing_delta = FileReadDouble(h);
      m_time_limit = FileReadInteger(h);
      m_activation_bound = FileReadDouble(h);
      m_trailing_on = FileReadInteger(h) != 0;
      m_trailing_trigger = FileReadDouble(h);
      return ArraySize(m_prices) == ArraySize(m_orders) && ArraySize(m_lots) == ArraySize(m_orders);
     }
   virtual string     Describe(void)
     {
      return StringFormat("%s %s DCA %d/%d filled lots=%.2f avg=%s pnl=%.3f%%", m_level_id, HbSideName(m_side),
                          m_placed - m_pending, ArraySize(m_prices), m_filled,
                          DoubleToString(m_avg_price, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS)), m_pnl_pct * 100.0);
     }
  };

//+------------------------------------------------------------------+
//| GridExecutor: evenly spaced levels between start and end price,  |
//| each level opens with a limit order and exits at its take profit |
//+------------------------------------------------------------------+
enum ENUM_HB_GRID_LEVEL_STATE
  {
   HB_LEVEL_NOT_ACTIVE = 0,
   HB_LEVEL_OPEN_ORDER_PLACED,
   HB_LEVEL_OPEN_ORDER_FILLED,
   HB_LEVEL_CLOSE_ORDER_PLACED,
   HB_LEVEL_COMPLETE
  };

class CHbGridExecutor : public CHbExecutor
  {
protected:
   double             m_start_price;
   double             m_end_price;
   double             m_limit_price;
   double             m_total_lots;
   double             m_min_order_lots;
   double             m_min_spread;
   int                m_max_open_orders;
   int                m_max_orders_per_batch;
   int                m_order_frequency;
   double             m_activation_bounds;
   double             m_safe_extra_spread;
   HbTripleBarrier    m_tb;
   bool               m_keep_on_limit;
   bool               m_initialized;
   double             m_lvl_price[];
   double             m_lvl_lots[];
   ulong              m_lvl_order[];
   double             m_level_tp;
   datetime           m_max_open_ts;
   bool               m_trailing_on;
   double             m_trailing_trigger;
   int                m_completed_cycles;
   // live values
   int                m_state[];
   double             m_mid;
   double             m_break_even;
   double             m_position_lots;
   double             m_pnl_pct;
   double             m_upnl;

   bool               IsExpired(void) const
     {
      return m_tb.time_limit > 0 && HbNow() >= m_timestamp + m_tb.time_limit;
     }
   double             TakeProfitPrice(const int i) const
     {
      return m_lvl_price[i] * (1.0 + (int)m_side * m_level_tp);
     }
   void               GenerateLevels(void)
     {
      double price = HbMid(m_symbol);
      double step = HbVolumeStep(m_symbol);
      double min_lots = MathMax(m_min_order_lots, HbVolumeMin(m_symbol));
      double grid_range = (m_end_price - m_start_price) / m_start_price;
      double min_step = MathMax(m_min_spread, HbTickSize(m_symbol) / price);
      int max_possible = (int)MathFloor(m_total_lots / min_lots + 1e-9);
      int n;
      double lots;
      if(max_possible == 0)
        {
         n = 1;
         lots = min_lots;
        }
      else
        {
         int max_by_step = (int)MathFloor(grid_range / min_step);
         n = (int)MathMax(1, MathMin(max_possible, max_by_step));
         lots = MathMax(min_lots, MathFloor(m_total_lots / n / step + 1e-9) * step);
         n = (int)MathMin((double)n, MathFloor(m_total_lots / lots + 1e-9));
        }
      n = (int)MathMax(1, n);
      ArrayResize(m_lvl_price, n);
      ArrayResize(m_lvl_lots, n);
      ArrayResize(m_lvl_order, n);
      ArrayResize(m_state, n);
      double grid_step;
      if(n > 1)
        {
         for(int i = 0; i < n; i++)
            m_lvl_price[i] = m_start_price + (m_end_price - m_start_price) * i / (n - 1);
         grid_step = grid_range / (n - 1);
        }
      else
        {
         m_lvl_price[0] = (m_start_price + m_end_price) / 2.0;
         grid_step = grid_range;
        }
      for(int i = 0; i < n; i++)
        {
         m_lvl_lots[i] = HbNormLots(m_symbol, lots);
         m_lvl_order[i] = 0;
         m_state[i] = HB_LEVEL_NOT_ACTIVE;
        }
      m_level_tp = m_tb.take_profit;
      HbLog(StringFormat("grid %s %s: %d levels %s-%s, %.2f lots per level, step %.4f%%", m_level_id,
                         HbSideName(m_side), n, DoubleToString(m_start_price, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS)),
                         DoubleToString(m_end_price, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS)), lots, grid_step * 100.0));
      m_initialized = true;
     }
   void               UpdateLevels(void)
     {
      m_break_even = 0; m_position_lots = 0; m_upnl = 0;
      double notional = 0;
      int n = ArraySize(m_lvl_order);
      ArrayResize(m_state, n);
      for(int i = 0; i < n; i++)
        {
         ulong o = m_lvl_order[i];
         if(o == 0)
           {
            m_state[i] = HB_LEVEL_NOT_ACTIVE;
            continue;
           }
         ulong pos = HbFindPosition(o);
         if(pos > 0 && PositionSelectByTicket(pos))
           {
            double v = PositionGetDouble(POSITION_VOLUME);
            m_position_lots += v;
            notional += v * PositionGetDouble(POSITION_PRICE_OPEN);
            m_upnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            m_state[i] = PositionGetDouble(POSITION_TP) > 0 ? HB_LEVEL_CLOSE_ORDER_PLACED : HB_LEVEL_OPEN_ORDER_FILLED;
            continue;
           }
         if(HbOrderIsPending(o))
           {
            m_state[i] = HB_LEVEL_OPEN_ORDER_PLACED;
            continue;
           }
         double filled = HbHistoryFilledVolume(o);
         if(filled < 0)
           {
            m_state[i] = HB_LEVEL_OPEN_ORDER_PLACED; // not synchronised yet
            continue;
           }
         if(filled > 0)
           {
            // the level went through open -> close: book it and make it available again
            double profit, price;
            ENUM_DEAL_REASON reason;
            if(HbClosedPositionResult(o, profit, price, reason))
               m_realized_pnl += profit;
            m_completed_cycles++;
           }
         m_lvl_order[i] = 0;
         m_state[i] = HB_LEVEL_NOT_ACTIVE;
        }
      if(m_position_lots > 0)
        {
         m_break_even = notional / m_position_lots;
         m_pnl_pct = (int)m_side * (m_mid - m_break_even) / m_break_even;
        }
      else
         m_pnl_pct = 0;
     }
   ENUM_HB_CLOSE_TYPE BarrierTriggered(bool &keep)
     {
      keep = false;
      if(m_tb.stop_loss > 0 && m_position_lots > 0 && m_pnl_pct <= -m_tb.stop_loss)
         return HB_CLOSE_STOP_LOSS;
      if(m_limit_price > 0 && ((m_side == HB_BUY && m_mid <= m_limit_price) || (m_side == HB_SELL && m_mid >= m_limit_price)))
        {
         keep = m_keep_on_limit;
         return keep ? HB_CLOSE_POSITION_HOLD : HB_CLOSE_STOP_LOSS;
        }
      if(IsExpired())
         return HB_CLOSE_TIME_LIMIT;
      if(m_tb.HasTrailing() && m_position_lots > 0)
        {
         if(!m_trailing_on)
           {
            if(m_pnl_pct > m_tb.trailing_activation)
              {
               m_trailing_on = true;
               m_trailing_trigger = m_pnl_pct - m_tb.trailing_delta;
              }
           }
         else
           {
            if(m_pnl_pct < m_trailing_trigger)
               return HB_CLOSE_TRAILING_STOP;
            if(m_pnl_pct - m_tb.trailing_delta > m_trailing_trigger)
               m_trailing_trigger = m_pnl_pct - m_tb.trailing_delta;
           }
        }
      if((m_side == HB_BUY && m_mid > m_end_price) || (m_side == HB_SELL && m_mid < m_start_price))
         return HB_CLOSE_TAKE_PROFIT;
      return HB_CLOSE_NONE;
     }
   void               PlaceOpenOrders(void)
     {
      int n = ArraySize(m_lvl_order);
      int n_open = 0;
      for(int i = 0; i < n; i++)
         if(m_state[i] == HB_LEVEL_OPEN_ORDER_PLACED)
            n_open++;
      if(m_max_open_ts > HbNow() - m_order_frequency || n_open >= m_max_open_orders)
         return;
      // candidates: inactive levels inside the activation bounds, closest to the mid price first
      int cand[];
      int nc = 0;
      for(int i = 0; i < n; i++)
        {
         if(m_state[i] != HB_LEVEL_NOT_ACTIVE)
            continue;
         if(m_activation_bounds > 0)
           {
            if(m_side == HB_BUY && m_lvl_price[i] < m_mid * (1.0 - m_activation_bounds))
               continue;
            if(m_side == HB_SELL && m_lvl_price[i] > m_mid * (1.0 + m_activation_bounds))
               continue;
           }
         ArrayResize(cand, nc + 1);
         cand[nc++] = i;
        }
      for(int a = 0; a < nc; a++)
         for(int b = a + 1; b < nc; b++)
            if(MathAbs(m_lvl_price[cand[b]] - m_mid) < MathAbs(m_lvl_price[cand[a]] - m_mid))
              {
               int t = cand[a];
               cand[a] = cand[b];
               cand[b] = t;
              }
      int batch = m_max_orders_per_batch > 0 ? m_max_orders_per_batch : nc;
      double bid = HbBid(m_symbol), ask = HbAsk(m_symbol);
      for(int k = 0; k < nc && k < batch; k++)
        {
         int i = cand[k];
         double price = m_lvl_price[i];
         if(m_side == HB_BUY && price >= ask)
            price = ask * (1.0 - m_safe_extra_spread);
         if(m_side == HB_SELL && price <= bid)
            price = bid * (1.0 + m_safe_extra_spread);
         double tp = (m_activation_bounds > 0 || m_level_tp <= 0) ? 0.0 : TakeProfitPrice(i);
         ulong t = HbPlaceOpen(m_symbol, m_side, m_tb.open_order_type, m_lvl_lots[i], price, 0, tp,
                               TradeComment() + " L" + IntegerToString(i));
         m_max_open_ts = HbNow();
         if(t > 0)
           {
            m_lvl_order[i] = t;
            m_state[i] = HB_LEVEL_OPEN_ORDER_PLACED;
           }
        }
     }
   void               ManageCloseOrders(void)
     {
      if(m_level_tp <= 0)
         return;
      int n = ArraySize(m_lvl_order);
      double bid = HbBid(m_symbol), ask = HbAsk(m_symbol);
      for(int i = 0; i < n; i++)
        {
         if(m_state[i] != HB_LEVEL_OPEN_ORDER_FILLED && m_state[i] != HB_LEVEL_CLOSE_ORDER_PLACED)
            continue;
         ulong pos = HbFindPosition(m_lvl_order[i]);
         if(pos == 0 || !PositionSelectByTicket(pos))
            continue;
         double target = TakeProfitPrice(i);
         // take profit already reached (or can't rest on the server this close): exit at market
         if((m_side == HB_BUY && bid >= target) || (m_side == HB_SELL && ask <= target))
           {
            HbClosePositionByTicket(pos);
            continue;
           }
         bool want = true;
         if(m_activation_bounds > 0)
            want = MathAbs(target - m_mid) / m_mid < m_activation_bounds;
         double cur_tp = PositionGetDouble(POSITION_TP);
         double cur_sl = PositionGetDouble(POSITION_SL);
         if(want)
           {
            double sl = 0, tp = target;
            HbSanitizeStops(m_symbol, m_side, m_side == HB_BUY ? bid : ask, sl, tp);
            if(tp > 0 && MathAbs(tp - cur_tp) >= HbTickSize(m_symbol) / 2)
               g_hb_trade.PositionModify(pos, cur_sl, tp);
           }
         else
            if(cur_tp > 0)
               g_hb_trade.PositionModify(pos, cur_sl, 0);
        }
     }
   void               CancelFarOpenOrders(void)
     {
      if(m_activation_bounds <= 0)
         return;
      for(int i = 0; i < ArraySize(m_lvl_order); i++)
         if(m_state[i] == HB_LEVEL_OPEN_ORDER_PLACED && OrderSelect(m_lvl_order[i]))
           {
            double p = OrderGetDouble(ORDER_PRICE_OPEN);
            if(MathAbs(p - m_mid) / m_mid > m_activation_bounds)
               HbCancelOrder(m_lvl_order[i]);
           }
     }
   void               Shutdown(void)
     {
      bool busy = false;
      for(int i = 0; i < ArraySize(m_lvl_order); i++)
        {
         ulong o = m_lvl_order[i];
         if(o == 0)
            continue;
         if(HbOrderIsPending(o))
           {
            HbCancelOrder(o);
            busy = true;
           }
         ulong pos = HbFindPosition(o);
         if(pos > 0 && !m_keep_position)
           {
            HbClosePositionByTicket(pos);
            busy = true;
           }
        }
      if(busy)
         return;
      for(int i = 0; i < ArraySize(m_lvl_order); i++)
        {
         double profit, price;
         ENUM_DEAL_REASON reason;
         if(m_lvl_order[i] != 0 && HbClosedPositionResult(m_lvl_order[i], profit, price, reason))
            m_realized_pnl += profit;
        }
      Terminate(m_close_type);
     }

public:
                      CHbGridExecutor(void)
     {
      m_start_price = 0; m_end_price = 0; m_limit_price = 0; m_total_lots = 0; m_min_order_lots = 0;
      m_min_spread = 0.0005; m_max_open_orders = 5; m_max_orders_per_batch = 0; m_order_frequency = 0;
      m_activation_bounds = 0; m_safe_extra_spread = 0.0001; m_keep_on_limit = false; m_initialized = false;
      m_level_tp = 0; m_max_open_ts = 0; m_trailing_on = false; m_trailing_trigger = 0; m_completed_cycles = 0;
      m_mid = 0; m_break_even = 0; m_position_lots = 0; m_pnl_pct = 0; m_upnl = 0;
      m_tb.Init();
     }
   void               Setup(const string sym, const ENUM_HB_SIDE side, const double start_price, const double end_price,
                            const double limit_price, const double total_lots, const double min_order_lots,
                            const double min_spread, const int max_open_orders, const int max_orders_per_batch,
                            const int order_frequency, const double activation_bounds, const HbTripleBarrier &tb,
                            const bool keep_position, const string level_id)
     {
      m_symbol = sym;
      m_side = side;
      m_start_price = start_price;
      m_end_price = end_price;
      m_limit_price = limit_price;
      m_total_lots = total_lots;
      m_min_order_lots = min_order_lots;
      m_min_spread = min_spread;
      m_max_open_orders = max_open_orders;
      m_max_orders_per_batch = max_orders_per_batch;
      m_order_frequency = order_frequency;
      m_activation_bounds = activation_bounds;
      m_tb = tb;
      m_keep_on_limit = keep_position;
      m_level_id = level_id;
     }
   virtual int        ExecType(void) const { return HB_EXEC_GRID; }
   virtual bool       IsTrading(void) { return m_position_lots > 0; }
   virtual double     FilledLots(void) { return m_position_lots; }
   virtual double     NetPnlPct(void) { return m_pnl_pct; }
   virtual double     UnrealizedPnl(void) { return m_upnl; }
   virtual void       PositionIds(ulong &ids[])
     {
      if(m_status == HB_TERMINATED)
         return;
      for(int i = 0; i < ArraySize(m_lvl_order); i++)
         if(m_lvl_order[i] != 0 && HbFindPosition(m_lvl_order[i]) > 0)
           {
            int n = ArraySize(ids);
            ArrayResize(ids, n + 1);
            ids[n] = m_lvl_order[i];
           }
     }

   virtual void       Process(void)
     {
      if(m_status == HB_TERMINATED)
         return;
      if(!m_initialized)
         GenerateLevels();
      m_mid = HbMid(m_symbol);
      UpdateLevels();
      if(m_status == HB_SHUTTING_DOWN)
        {
         Shutdown();
         return;
        }
      bool keep = false;
      ENUM_HB_CLOSE_TYPE trigger = BarrierTriggered(keep);
      if(trigger != HB_CLOSE_NONE)
        {
         BeginShutdown(trigger, keep);
         Shutdown();
         return;
        }
      PlaceOpenOrders();
      ManageCloseOrders();
      CancelFarOpenOrders();
     }

   virtual void       Save(const int h)
     {
      CHbExecutor::Save(h);
      FileWriteDouble(h, m_start_price);
      FileWriteDouble(h, m_end_price);
      FileWriteDouble(h, m_limit_price);
      FileWriteDouble(h, m_total_lots);
      FileWriteDouble(h, m_min_order_lots);
      FileWriteDouble(h, m_min_spread);
      FileWriteInteger(h, m_max_open_orders);
      FileWriteInteger(h, m_max_orders_per_batch);
      FileWriteInteger(h, m_order_frequency);
      FileWriteDouble(h, m_activation_bounds);
      HbWriteBarrier(h, m_tb);
      FileWriteInteger(h, m_keep_on_limit ? 1 : 0);
      FileWriteInteger(h, m_initialized ? 1 : 0);
      HbWriteDoubles(h, m_lvl_price);
      HbWriteDoubles(h, m_lvl_lots);
      HbWriteTickets(h, m_lvl_order);
      FileWriteDouble(h, m_level_tp);
      FileWriteLong(h, (long)m_max_open_ts);
      FileWriteInteger(h, m_trailing_on ? 1 : 0);
      FileWriteDouble(h, m_trailing_trigger);
      FileWriteInteger(h, m_completed_cycles);
     }
   virtual bool       Load(const int h)
     {
      if(!CHbExecutor::Load(h))
         return false;
      m_start_price = FileReadDouble(h);
      m_end_price = FileReadDouble(h);
      m_limit_price = FileReadDouble(h);
      m_total_lots = FileReadDouble(h);
      m_min_order_lots = FileReadDouble(h);
      m_min_spread = FileReadDouble(h);
      m_max_open_orders = FileReadInteger(h);
      m_max_orders_per_batch = FileReadInteger(h);
      m_order_frequency = FileReadInteger(h);
      m_activation_bounds = FileReadDouble(h);
      HbReadBarrier(h, m_tb);
      m_keep_on_limit = FileReadInteger(h) != 0;
      m_initialized = FileReadInteger(h) != 0;
      HbReadDoubles(h, m_lvl_price);
      HbReadDoubles(h, m_lvl_lots);
      HbReadTickets(h, m_lvl_order);
      m_level_tp = FileReadDouble(h);
      m_max_open_ts = (datetime)FileReadLong(h);
      m_trailing_on = FileReadInteger(h) != 0;
      m_trailing_trigger = FileReadDouble(h);
      m_completed_cycles = FileReadInteger(h);
      ArrayResize(m_state, ArraySize(m_lvl_order));
      return ArraySize(m_lvl_price) == ArraySize(m_lvl_order);
     }
   virtual string     Describe(void)
     {
      int counts[5] = {0, 0, 0, 0, 0};
      for(int i = 0; i < ArraySize(m_state); i++)
         if(m_state[i] >= 0 && m_state[i] < 5)
            counts[m_state[i]]++;
      int d = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      return StringFormat("%s %s grid %s-%s levels=%d idle=%d open=%d filled=%d tp=%d cycles=%d lots=%.2f be=%s pnl=%.3f%% realized=%.2f",
                          m_level_id, HbSideName(m_side), DoubleToString(m_start_price, d), DoubleToString(m_end_price, d),
                          ArraySize(m_state), counts[0], counts[1], counts[2], counts[3], m_completed_cycles,
                          m_position_lots, DoubleToString(m_break_even, d), m_pnl_pct * 100.0, m_realized_pnl);
     }
  };

//+------------------------------------------------------------------+
//| Factory used when restoring saved state                          |
//+------------------------------------------------------------------+
CHbExecutor *HbNewExecutor(const int type)
  {
   switch(type)
     {
      case HB_EXEC_POSITION: return new CHbPositionExecutor();
      case HB_EXEC_DCA:      return new CHbDCAExecutor();
      case HB_EXEC_GRID:     return new CHbGridExecutor();
     }
   return NULL;
  }

#endif

//+------------------------------------------------------------------+
//| Hummingbot MT5 - core types and trading helpers                  |
//| Port of hummingbot/strategy_v2 (Apache-2.0) to MQL5              |
//+------------------------------------------------------------------+
#ifndef HB_CORE_MQH
#define HB_CORE_MQH

#include <Trade\Trade.mqh>
#include <Arrays\ArrayObj.mqh>

#define HB_STATE_VERSION 3

// Hummingbot TradeType
enum ENUM_HB_SIDE
  {
   HB_BUY  = 1,   // Buy
   HB_SELL = -1   // Sell
  };

// Hummingbot OrderType (MARKET / LIMIT / LIMIT_MAKER)
enum ENUM_HB_ORDER_TYPE
  {
   HB_ORDER_MARKET      = 0, // Market
   HB_ORDER_LIMIT       = 1, // Limit (crosses the spread if marketable)
   HB_ORDER_LIMIT_MAKER = 2  // Limit maker (never crosses the spread)
  };

// Hummingbot CloseType
enum ENUM_HB_CLOSE_TYPE
  {
   HB_CLOSE_NONE = 0,
   HB_CLOSE_TAKE_PROFIT,
   HB_CLOSE_STOP_LOSS,
   HB_CLOSE_TIME_LIMIT,
   HB_CLOSE_TRAILING_STOP,
   HB_CLOSE_EARLY_STOP,
   HB_CLOSE_POSITION_HOLD,
   HB_CLOSE_FAILED,
   HB_CLOSE_COMPLETED
  };

// Hummingbot RunnableStatus
enum ENUM_HB_STATUS
  {
   HB_RUNNING = 0,
   HB_SHUTTING_DOWN,
   HB_TERMINATED
  };

// Executor type ids, used when restoring state from disk
enum ENUM_HB_EXECUTOR_TYPE
  {
   HB_EXEC_POSITION = 1,
   HB_EXEC_DCA      = 2,
   HB_EXEC_GRID     = 3
  };

//+------------------------------------------------------------------+
//| Triple barrier: stop loss, take profit, time limit, trailing stop |
//| All percentages are fractions (0.02 = 2%), like Hummingbot.       |
//+------------------------------------------------------------------+
struct HbTripleBarrier
  {
   double            stop_loss;           // 0 = disabled
   double            take_profit;         // 0 = disabled
   int               time_limit;          // seconds, 0 = disabled
   double            trailing_activation; // 0 = trailing disabled
   double            trailing_delta;
   ENUM_HB_ORDER_TYPE open_order_type;
   ENUM_HB_ORDER_TYPE take_profit_order_type;

   void              Init(void)
     {
      stop_loss = 0; take_profit = 0; time_limit = 0;
      trailing_activation = 0; trailing_delta = 0;
      open_order_type = HB_ORDER_MARKET;
      take_profit_order_type = HB_ORDER_LIMIT;
     }
   bool              HasTrailing(void) const { return trailing_activation > 0 && trailing_delta > 0; }
  };

//+------------------------------------------------------------------+
//| Globals shared by every executor                                 |
//+------------------------------------------------------------------+
CTrade   g_hb_trade;
long     g_hb_magic = 0;
string   g_hb_name = "HB";
bool     g_hb_verbose = true;
int      g_hb_id_counter = 0;

void HbInit(const string name, const long magic, const int deviation_points)
  {
   g_hb_name = name;
   g_hb_magic = magic;
   g_hb_trade.SetExpertMagicNumber((ulong)magic);
   g_hb_trade.SetDeviationInPoints(deviation_points);
   g_hb_trade.SetMarginMode();
   g_hb_trade.LogLevel(LOG_LEVEL_ERRORS);
  }

void HbLog(const string msg)
  {
   if(g_hb_verbose)
      Print(g_hb_name, ": ", msg);
  }

bool HbIsTester(void) { return (bool)MQLInfoInteger(MQL_TESTER); }

datetime HbNow(void)
  {
   if(HbIsTester())
      return TimeCurrent();
   datetime t = TimeTradeServer();
   return t > 0 ? t : TimeCurrent();
  }

string HbNewId(void)
  {
   g_hb_id_counter++;
   return StringFormat("%I64d-%d", (long)HbNow(), g_hb_id_counter);
  }

bool HbIsHedgingAccount(void)
  {
   return AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
  }

string HbSideName(const ENUM_HB_SIDE side) { return side == HB_BUY ? "BUY" : "SELL"; }

string HbCloseTypeName(const ENUM_HB_CLOSE_TYPE t)
  {
   switch(t)
     {
      case HB_CLOSE_TAKE_PROFIT:   return "TAKE_PROFIT";
      case HB_CLOSE_STOP_LOSS:     return "STOP_LOSS";
      case HB_CLOSE_TIME_LIMIT:    return "TIME_LIMIT";
      case HB_CLOSE_TRAILING_STOP: return "TRAILING_STOP";
      case HB_CLOSE_EARLY_STOP:    return "EARLY_STOP";
      case HB_CLOSE_POSITION_HOLD: return "POSITION_HOLD";
      case HB_CLOSE_FAILED:        return "FAILED";
      case HB_CLOSE_COMPLETED:     return "COMPLETED";
     }
   return "NONE";
  }

//+------------------------------------------------------------------+
//| Prices and volumes                                               |
//+------------------------------------------------------------------+
double HbBid(const string sym) { return SymbolInfoDouble(sym, SYMBOL_BID); }
double HbAsk(const string sym) { return SymbolInfoDouble(sym, SYMBOL_ASK); }
double HbMid(const string sym) { return (HbBid(sym) + HbAsk(sym)) / 2.0; }
double HbPoint(const string sym) { return SymbolInfoDouble(sym, SYMBOL_POINT); }

double HbTickSize(const string sym)
  {
   double ts = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   return ts > 0 ? ts : HbPoint(sym);
  }

double HbNormPrice(const string sym, const double price)
  {
   double ts = HbTickSize(sym);
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   return NormalizeDouble(MathRound(price / ts) * ts, digits);
  }

// Minimum distance between the market and a pending price / SL / TP
double HbStopsDistance(const string sym)
  {
   long stops = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL);
   return (double)MathMax(stops, freeze) * HbPoint(sym);
  }

double HbVolumeMin(const string sym)  { return SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN); }
double HbVolumeStep(const string sym) { double s = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP); return s > 0 ? s : 0.01; }

// Round lots down to the volume step, clamp to [min, max]. Returns 0 when below the minimum and !clamp_to_min.
double HbNormLots(const string sym, const double lots, const bool clamp_to_min = true)
  {
   double step = HbVolumeStep(sym);
   double vmin = HbVolumeMin(sym);
   double vmax = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double v = MathFloor(lots / step + 1e-9) * step;
   if(v < vmin)
      v = clamp_to_min ? vmin : 0.0;
   if(vmax > 0 && v > vmax)
      v = vmax;
   int vd = (int)MathMax(0.0, MathCeil(-MathLog10(step) - 1e-9));
   return NormalizeDouble(v, vd);
  }

// Account-currency notional of one lot at the given price (stands in for Hummingbot's "amount quote")
double HbLotNotional(const string sym, const double price)
  {
   double tick_value = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = HbTickSize(sym);
   if(tick_value <= 0 || tick_size <= 0)
      return 0.0;
   return price / tick_size * tick_value;
  }

double HbPnlPct(const ENUM_HB_SIDE side, const double entry, const double bid, const double ask)
  {
   if(entry <= 0)
      return 0.0;
   if(side == HB_BUY)
      return (bid - entry) / entry;
   return (entry - ask) / entry;
  }

//+------------------------------------------------------------------+
//| Parsing comma-separated input lists ("0.01,0.02")                |
//+------------------------------------------------------------------+
int HbParseList(const string text, double &out[])
  {
   ArrayResize(out, 0);
   string parts[];
   int n = StringSplit(text, StringGetCharacter(",", 0), parts);
   int count = 0;
   for(int i = 0; i < n; i++)
     {
      string p = parts[i];
      StringTrimLeft(p);
      StringTrimRight(p);
      if(StringLen(p) == 0)
         continue;
      ArrayResize(out, count + 1);
      out[count] = StringToDouble(p);
      count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Orders and positions                                             |
//+------------------------------------------------------------------+
// Finds the open position created by an order (position identifier == opening order ticket).
// Selects the position and returns its ticket, or 0.
ulong HbFindPosition(const ulong identifier)
  {
   if(identifier == 0)
      return 0;
   if(PositionSelectByTicket(identifier) && (ulong)PositionGetInteger(POSITION_IDENTIFIER) == identifier)
      return identifier;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == identifier)
         return ticket;
     }
   return 0;
  }

bool HbOrderIsPending(const ulong ticket)
  {
   if(ticket == 0 || !OrderSelect(ticket))
      return false;
   ENUM_ORDER_STATE st = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
   return st == ORDER_STATE_PLACED || st == ORDER_STATE_PARTIAL || st == ORDER_STATE_STARTED;
  }

// Volume filled by a finished order: >=0 when the order is in history, -1 when not found yet.
double HbHistoryFilledVolume(const ulong ticket)
  {
   if(ticket == 0 || !HistoryOrderSelect(ticket))
      return -1.0;
   double initial = HistoryOrderGetDouble(ticket, ORDER_VOLUME_INITIAL);
   double current = HistoryOrderGetDouble(ticket, ORDER_VOLUME_CURRENT);
   return MathMax(0.0, initial - current);
  }

// Realized result of a closed position: net profit (profit+swap+commission+fee) and the close reason
bool HbClosedPositionResult(const ulong identifier, double &profit, double &close_price, ENUM_DEAL_REASON &reason)
  {
   profit = 0.0; close_price = 0.0; reason = DEAL_REASON_CLIENT;
   if(identifier == 0 || !HistorySelectByPosition(identifier))
      return false;
   int n = HistoryDealsTotal();
   bool closed = false;
   for(int i = 0; i < n; i++)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      profit += HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP) +
                HistoryDealGetDouble(deal, DEAL_COMMISSION) + HistoryDealGetDouble(deal, DEAL_FEE);
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
        {
         closed = true;
         close_price = HistoryDealGetDouble(deal, DEAL_PRICE);
         reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(deal, DEAL_REASON);
        }
     }
   return closed;
  }

// Makes SL/TP valid for a reference price (pending price, or bid/ask for a position). Invalid levels become 0
// and the executor enforces them client-side instead.
void HbSanitizeStops(const string sym, const ENUM_HB_SIDE side, const double ref_price, double &sl, double &tp)
  {
   double dist = HbStopsDistance(sym) + HbTickSize(sym);
   if(sl > 0)
     {
      sl = HbNormPrice(sym, sl);
      if(side == HB_BUY && sl > ref_price - dist)
         sl = 0;
      if(side == HB_SELL && sl < ref_price + dist)
         sl = 0;
     }
   if(tp > 0)
     {
      tp = HbNormPrice(sym, tp);
      if(side == HB_BUY && tp < ref_price + dist)
         tp = 0;
      if(side == HB_SELL && tp > ref_price - dist)
         tp = 0;
     }
  }

// Places an opening order. LIMIT orders that would cross the spread are sent as market orders (they would fill as
// taker on an exchange); LIMIT_MAKER orders are pulled back just behind the touch. Returns the order ticket, which
// is also the identifier of the position it opens.
ulong HbPlaceOpen(const string sym, const ENUM_HB_SIDE side, ENUM_HB_ORDER_TYPE type, const double lots,
                  double price, double sl, double tp, const string comment)
  {
   double vol = HbNormLots(sym, lots);
   if(vol <= 0)
      return 0;
   double bid = HbBid(sym), ask = HbAsk(sym);
   double dist = HbStopsDistance(sym) + HbTickSize(sym);
   if(type != HB_ORDER_MARKET)
     {
      if(side == HB_BUY && price > ask - dist)
        {
         if(type == HB_ORDER_LIMIT && price >= ask)
            type = HB_ORDER_MARKET;
         else
            price = ask - dist;
        }
      if(side == HB_SELL && price < bid + dist)
        {
         if(type == HB_ORDER_LIMIT && price <= bid)
            type = HB_ORDER_MARKET;
         else
            price = bid + dist;
        }
     }
   bool ok;
   if(type == HB_ORDER_MARKET)
     {
      double ref = side == HB_BUY ? bid : ask;
      HbSanitizeStops(sym, side, ref, sl, tp);
      ok = side == HB_BUY ? g_hb_trade.Buy(vol, sym, 0, sl, tp, comment) : g_hb_trade.Sell(vol, sym, 0, sl, tp, comment);
      if(!ok && g_hb_trade.ResultRetcode() == TRADE_RETCODE_INVALID_STOPS)
         ok = side == HB_BUY ? g_hb_trade.Buy(vol, sym, 0, 0, 0, comment) : g_hb_trade.Sell(vol, sym, 0, 0, 0, comment);
     }
   else
     {
      price = HbNormPrice(sym, price);
      HbSanitizeStops(sym, side, price, sl, tp);
      ok = side == HB_BUY ? g_hb_trade.BuyLimit(vol, price, sym, sl, tp, ORDER_TIME_GTC, 0, comment)
                          : g_hb_trade.SellLimit(vol, price, sym, sl, tp, ORDER_TIME_GTC, 0, comment);
     }
   uint rc = g_hb_trade.ResultRetcode();
   if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED && rc != TRADE_RETCODE_DONE_PARTIAL))
     {
      HbLog(StringFormat("order failed %s %s %.2f @ %s: %d %s", HbSideName(side), sym, vol,
                         DoubleToString(price, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)), rc,
                         g_hb_trade.ResultRetcodeDescription()));
      return 0;
     }
   return g_hb_trade.ResultOrder();
  }

bool HbCancelOrder(const ulong ticket)
  {
   if(!HbOrderIsPending(ticket))
      return true;
   return g_hb_trade.OrderDelete(ticket);
  }

bool HbClosePositionByTicket(const ulong ticket)
  {
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return true;
   return g_hb_trade.PositionClose(ticket);
  }

// Moves the server-side SL/TP of a position when they differ from the wanted levels by more than a tick.
// The position must be selected.
void HbEnsureStops(const ulong pos_ticket, const string sym, const ENUM_HB_SIDE side, double sl, double tp)
  {
   if(pos_ticket == 0 || !PositionSelectByTicket(pos_ticket))
      return;
   double ref = side == HB_BUY ? HbBid(sym) : HbAsk(sym);
   HbSanitizeStops(sym, side, ref, sl, tp);
   double cur_sl = PositionGetDouble(POSITION_SL);
   double cur_tp = PositionGetDouble(POSITION_TP);
   double ts = HbTickSize(sym);
   // never loosen an existing stop that is still valid
   if(sl == 0 && cur_sl > 0)
      sl = cur_sl;
   if(MathAbs(sl - cur_sl) < ts / 2 && MathAbs(tp - cur_tp) < ts / 2)
      return;
   g_hb_trade.PositionModify(pos_ticket, sl, tp);
  }

//+------------------------------------------------------------------+
//| Candles                                                          |
//+------------------------------------------------------------------+
// Copies the latest `count` candles, oldest first; the last element is the live (forming) candle, as in
// Hummingbot's candles feed.
bool HbGetCandles(const string sym, const ENUM_TIMEFRAMES tf, const int count,
                  double &open[], double &high[], double &low[], double &close[])
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   int got = CopyRates(sym, tf, 0, count, rates);
   if(got < count)
      return false;
   ArrayResize(open, got); ArrayResize(high, got); ArrayResize(low, got); ArrayResize(close, got);
   for(int i = 0; i < got; i++)
     {
      open[i] = rates[i].open;
      high[i] = rates[i].high;
      low[i] = rates[i].low;
      close[i] = rates[i].close;
     }
   return true;
  }

bool HbGetCloses(const string sym, const ENUM_TIMEFRAMES tf, const int count, double &close[])
  {
   ArraySetAsSeries(close, false);
   int got = CopyClose(sym, tf, 0, count, close);
   return got >= count;
  }

//+------------------------------------------------------------------+
//| Binary state file helpers                                        |
//+------------------------------------------------------------------+
void HbWriteString(const int h, const string s)
  {
   FileWriteInteger(h, StringLen(s));
   if(StringLen(s) > 0)
      FileWriteString(h, s);
  }

string HbReadString(const int h)
  {
   int len = FileReadInteger(h);
   if(len <= 0 || len > 4096)
      return "";
   return FileReadString(h, len);
  }

void HbWriteDoubles(const int h, const double &arr[])
  {
   int n = ArraySize(arr);
   FileWriteInteger(h, n);
   for(int i = 0; i < n; i++)
      FileWriteDouble(h, arr[i]);
  }

void HbReadDoubles(const int h, double &arr[])
  {
   int n = FileReadInteger(h);
   if(n < 0 || n > 100000)
      n = 0;
   ArrayResize(arr, n);
   for(int i = 0; i < n; i++)
      arr[i] = FileReadDouble(h);
  }

void HbWriteTickets(const int h, const ulong &arr[])
  {
   int n = ArraySize(arr);
   FileWriteInteger(h, n);
   for(int i = 0; i < n; i++)
      FileWriteLong(h, (long)arr[i]);
  }

void HbReadTickets(const int h, ulong &arr[])
  {
   int n = FileReadInteger(h);
   if(n < 0 || n > 100000)
      n = 0;
   ArrayResize(arr, n);
   for(int i = 0; i < n; i++)
      arr[i] = (ulong)FileReadLong(h);
  }

void HbWriteBarrier(const int h, const HbTripleBarrier &tb)
  {
   FileWriteDouble(h, tb.stop_loss);
   FileWriteDouble(h, tb.take_profit);
   FileWriteInteger(h, tb.time_limit);
   FileWriteDouble(h, tb.trailing_activation);
   FileWriteDouble(h, tb.trailing_delta);
   FileWriteInteger(h, (int)tb.open_order_type);
   FileWriteInteger(h, (int)tb.take_profit_order_type);
  }

void HbReadBarrier(const int h, HbTripleBarrier &tb)
  {
   tb.stop_loss = FileReadDouble(h);
   tb.take_profit = FileReadDouble(h);
   tb.time_limit = FileReadInteger(h);
   tb.trailing_activation = FileReadDouble(h);
   tb.trailing_delta = FileReadDouble(h);
   tb.open_order_type = (ENUM_HB_ORDER_TYPE)FileReadInteger(h);
   tb.take_profit_order_type = (ENUM_HB_ORDER_TYPE)FileReadInteger(h);
  }

#endif

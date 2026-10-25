//+------------------------------------------------------------------+
//| Hummingbot MT5 - symbol auto-tune                                |
//| Hummingbot's defaults were made for crypto pairs that move ~5%   |
//| a day. Auto-tune measures the symbol's own daily range (ATR) and |
//| bid/ask spread, then scales every percentage setting to it, so   |
//| the same defaults fit EURUSD, XAUUSD, indices or synthetics.     |
//+------------------------------------------------------------------+
#ifndef HB_AUTOTUNE_MQH
#define HB_AUTOTUNE_MQH

#include "Core.mqh"

#define HB_TUNE_MIN_FACTOR 0.02
#define HB_TUNE_MAX_FACTOR 3.0
#define HB_TUNE_ATR_BARS   14

double g_hb_tune = 1.0;        // multiplier applied to percentage settings
double g_hb_tune_floor = 0.0;  // smallest target distance, as a fraction of price
string g_hb_tune_info = "";

// Average true range over the last completed bars, as a fraction of the last close.
// The range is scaled to one day with the square root of time, so any timeframe can stand in for D1.
bool HbDailyRange(const string sym, const ENUM_TIMEFRAMES tf, double &range, double &spread_frac, string &source)
  {
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int need = HB_TUNE_ATR_BARS + 1;
   int got = 0;
   for(int attempt = 0; attempt < 10; attempt++)
     {
      got = CopyRates(sym, tf, 1, need, r);
      if(got >= 6 || HbIsTester())
         break;
      Sleep(300);  // history is still downloading
     }
   if(got < 6)
      return false;
   double tr_sum = 0, spread_sum = 0;
   int n = 0;
   for(int i = 1; i < got; i++)
     {
      double tr = MathMax(r[i].high, r[i - 1].close) - MathMin(r[i].low, r[i - 1].close);
      tr_sum += tr;
      spread_sum += r[i].spread;
      n++;
     }
   double last = r[got - 1].close;
   if(n == 0 || last <= 0 || tr_sum <= 0)
      return false;
   double scale = MathSqrt(86400.0 / PeriodSeconds(tf));
   range = tr_sum / n / last * MathMin(scale, 100.0);
   double avg_spread_points = spread_sum / n;
   if(avg_spread_points <= 0)
      avg_spread_points = (double)SymbolInfoInteger(sym, SYMBOL_SPREAD);
   spread_frac = avg_spread_points * HbPoint(sym) / last;
   source = EnumToString(tf);
   StringReplace(source, "PERIOD_", "");
   return true;
  }

// Measures the symbol (or the average of two symbols for pairs trading) and sets the tuning factor.
// enabled = false leaves every setting exactly as entered.
void HbAutoTuneInit(const bool enabled, const double reference_range, const double min_spreads,
                    const string sym, const string sym2 = "")
  {
   g_hb_tune = 1.0;
   g_hb_tune_floor = 0.0;
   if(!enabled || reference_range <= 0)
     {
      g_hb_tune_info = "auto-tune off: settings used as entered";
      return;
     }
   string syms[];
   int count = sym2 == "" ? 1 : 2;
   ArrayResize(syms, count);
   syms[0] = sym;
   if(count == 2)
      syms[1] = sym2;
   ENUM_TIMEFRAMES sources[] = {PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15};
   double range_sum = 0, spread_max = 0;
   string used = "";
   for(int s = 0; s < count; s++)
     {
      double range = 0, spread = 0;
      string src = "";
      bool ok = false;
      for(int k = 0; k < ArraySize(sources) && !ok; k++)
         ok = HbDailyRange(syms[s], sources[k], range, spread, src);
      if(!ok)
         ok = HbDailyRange(syms[s], (ENUM_TIMEFRAMES)Period(), range, spread, src);
      if(!ok)
        {
         g_hb_tune_info = "auto-tune: no price history for " + syms[s] + ", settings used as entered";
         Print(g_hb_tune_info);
         return;
        }
      range_sum += range;
      spread_max = MathMax(spread_max, spread);
      used += StringFormat("%s%s daily range %.3f%% (%s), spread %.4f%%", s > 0 ? "; " : "", syms[s], range * 100.0, src,
                           spread * 100.0);
     }
   double factor = range_sum / count / reference_range;
   g_hb_tune = MathMax(HB_TUNE_MIN_FACTOR, MathMin(HB_TUNE_MAX_FACTOR, factor));
   g_hb_tune_floor = MathMax(0.0, min_spreads) * spread_max;
   g_hb_tune_info = StringFormat("auto-tune x%.3f | %s | min target %.4f%%", g_hb_tune, used, g_hb_tune_floor * 100.0);
   Print(g_hb_tune_info);
  }

// A percentage setting that should follow volatility: entry offsets, ranges, thresholds.
double HbTune(const double frac) { return frac * g_hb_tune; }

// A profit or loss target: follows volatility but stays a few spreads away from the price. 0 stays off.
double HbTuneDist(const double frac)
  {
   if(frac <= 0)
      return frac;
   return MathMax(frac * g_hb_tune, g_hb_tune_floor);
  }

// Scales a comma separated list of fractions (spreads), keeping the order.
string HbTuneList(const string text, const bool as_distance)
  {
   double v[];
   int n = HbParseList(text, v);
   string out = "";
   for(int i = 0; i < n; i++)
     {
      double x = as_distance ? HbTuneDist(v[i]) : HbTune(v[i]);
      out += (i > 0 ? "," : "") + DoubleToString(x, 10);
     }
   return out;
  }

#endif

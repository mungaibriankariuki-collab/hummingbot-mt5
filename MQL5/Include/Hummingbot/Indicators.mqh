//+------------------------------------------------------------------+
//| Hummingbot MT5 - indicators                                      |
//| Same formulas as pandas_ta / TA-Lib used by Hummingbot, computed |
//| on oldest-first arrays. Undefined values are EMPTY_VALUE.        |
//+------------------------------------------------------------------+
#ifndef HB_INDICATORS_MQH
#define HB_INDICATORS_MQH

bool HbValid(const double v) { return v != EMPTY_VALUE; }

void HbFillEmpty(double &arr[], const int n)
  {
   ArrayResize(arr, n);
   for(int i = 0; i < n; i++)
      arr[i] = EMPTY_VALUE;
  }

// Simple moving average
void HbSMA(const double &src[], const int length, double &out[])
  {
   int n = ArraySize(src);
   HbFillEmpty(out, n);
   if(length <= 0 || n < length)
      return;
   double sum = 0;
   for(int i = 0; i < n; i++)
     {
      sum += src[i];
      if(i >= length)
         sum -= src[i - length];
      if(i >= length - 1)
         out[i] = sum / length;
     }
  }

// EMA seeded with the SMA of the first `length` valid values (TA-Lib / pandas_ta presma)
void HbEMA(const double &src[], const int length, double &out[])
  {
   int n = ArraySize(src);
   HbFillEmpty(out, n);
   if(length <= 0)
      return;
   int start = 0;
   while(start < n && !HbValid(src[start]))
      start++;
   if(n - start < length)
      return;
   double sum = 0;
   for(int i = start; i < start + length; i++)
      sum += src[i];
   int seed = start + length - 1;
   out[seed] = sum / length;
   double k = 2.0 / (length + 1.0);
   for(int i = seed + 1; i < n; i++)
      out[i] = src[i] * k + out[i - 1] * (1.0 - k);
  }

// Bollinger Bands (SMA, population standard deviation like pandas_ta ddof=0 / TA-Lib)
// bbp = %B, bbb = bandwidth in percent
void HbBBands(const double &close[], const int length, const double std_mult,
              double &lower[], double &middle[], double &upper[], double &bbp[], double &bbb[])
  {
   int n = ArraySize(close);
   HbSMA(close, length, middle);
   HbFillEmpty(lower, n); HbFillEmpty(upper, n); HbFillEmpty(bbp, n); HbFillEmpty(bbb, n);
   for(int i = length - 1; i < n; i++)
     {
      if(!HbValid(middle[i]))
         continue;
      double m = middle[i];
      double var = 0;
      for(int j = i - length + 1; j <= i; j++)
         var += (close[j] - m) * (close[j] - m);
      double sd = MathSqrt(var / length);
      upper[i] = m + std_mult * sd;
      lower[i] = m - std_mult * sd;
      double range = upper[i] - lower[i];
      bbp[i] = range != 0 ? (close[i] - lower[i]) / range : 0.5;
      bbb[i] = m != 0 ? 100.0 * range / m : 0.0;
     }
  }

// MACD line, signal line and histogram
void HbMACD(const double &close[], const int fast, const int slow, const int signal,
            double &macd[], double &macd_signal[], double &hist[])
  {
   int n = ArraySize(close);
   double ema_fast[], ema_slow[];
   HbEMA(close, fast, ema_fast);
   HbEMA(close, slow, ema_slow);
   HbFillEmpty(macd, n);
   for(int i = 0; i < n; i++)
      if(HbValid(ema_fast[i]) && HbValid(ema_slow[i]))
         macd[i] = ema_fast[i] - ema_slow[i];
   HbEMA(macd, signal, macd_signal);
   HbFillEmpty(hist, n);
   for(int i = 0; i < n; i++)
      if(HbValid(macd[i]) && HbValid(macd_signal[i]))
         hist[i] = macd[i] - macd_signal[i];
  }

// Wilder ATR (TA-Lib): seed with the SMA of the first `length` true ranges, then RMA
void HbATR(const double &high[], const double &low[], const double &close[], const int length, double &out[])
  {
   int n = ArraySize(close);
   HbFillEmpty(out, n);
   if(length <= 0 || n <= length)
      return;
   double tr[];
   ArrayResize(tr, n);
   tr[0] = high[0] - low[0];
   for(int i = 1; i < n; i++)
      tr[i] = MathMax(high[i] - low[i], MathMax(MathAbs(high[i] - close[i - 1]), MathAbs(low[i] - close[i - 1])));
   double sum = 0;
   for(int i = 1; i <= length; i++)
      sum += tr[i];
   out[length] = sum / length;
   for(int i = length + 1; i < n; i++)
      out[i] = (out[i - 1] * (length - 1) + tr[i]) / length;
  }

// Normalized ATR as a fraction of price (Hummingbot divides pandas_ta natr by 100)
void HbNATR(const double &high[], const double &low[], const double &close[], const int length, double &out[])
  {
   HbATR(high, low, close, length, out);
   int n = ArraySize(out);
   for(int i = 0; i < n; i++)
      if(HbValid(out[i]) && close[i] != 0)
         out[i] = out[i] / close[i];
  }

// SuperTrend (pandas_ta): trend line and direction (+1 / -1)
void HbSuperTrend(const double &high[], const double &low[], const double &close[], const int length,
                  const double multiplier, double &trend[], double &direction[])
  {
   int n = ArraySize(close);
   double atr[];
   HbATR(high, low, close, length, atr);
   double ub[], lb[];
   ArrayResize(ub, n); ArrayResize(lb, n);
   HbFillEmpty(trend, n);
   HbFillEmpty(direction, n);
   for(int i = 0; i < n; i++)
     {
      double hl2 = (high[i] + low[i]) / 2.0;
      if(HbValid(atr[i]))
        {
         ub[i] = hl2 + multiplier * atr[i];
         lb[i] = hl2 - multiplier * atr[i];
        }
      else
        {
         ub[i] = EMPTY_VALUE;
         lb[i] = EMPTY_VALUE;
        }
     }
   if(n == 0)
      return;
   direction[0] = 1;
   for(int i = 1; i < n; i++)
     {
      bool prev_ok = HbValid(ub[i - 1]) && HbValid(lb[i - 1]);
      if(prev_ok && close[i] > ub[i - 1])
         direction[i] = 1;
      else
         if(prev_ok && close[i] < lb[i - 1])
            direction[i] = -1;
         else
           {
            direction[i] = direction[i - 1];
            if(prev_ok && HbValid(lb[i]))
              {
               if(direction[i] > 0 && lb[i] < lb[i - 1])
                  lb[i] = lb[i - 1];
               if(direction[i] < 0 && ub[i] > ub[i - 1])
                  ub[i] = ub[i - 1];
              }
           }
      trend[i] = direction[i] > 0 ? lb[i] : ub[i];
     }
  }

double HbMean(const double &arr[])
  {
   int n = ArraySize(arr);
   if(n == 0)
      return 0;
   double s = 0;
   for(int i = 0; i < n; i++)
      s += arr[i];
   return s / n;
  }

// Population standard deviation (numpy default)
double HbStd(const double &arr[])
  {
   int n = ArraySize(arr);
   if(n == 0)
      return 0;
   double m = HbMean(arr);
   double s = 0;
   for(int i = 0; i < n; i++)
      s += (arr[i] - m) * (arr[i] - m);
   return MathSqrt(s / n);
  }

// Copies the valid tail of a series
int HbValidTail(const double &src[], double &out[])
  {
   int n = ArraySize(src);
   int start = 0;
   while(start < n && !HbValid(src[start]))
      start++;
   ArrayResize(out, n - start);
   for(int i = start; i < n; i++)
      out[i - start] = src[i];
   return n - start;
  }

// Ordinary least squares y = alpha + beta * x
bool HbLinReg(const double &x[], const double &y[], double &alpha, double &beta)
  {
   int n = MathMin(ArraySize(x), ArraySize(y));
   if(n < 2)
      return false;
   double mx = 0, my = 0;
   for(int i = 0; i < n; i++)
     {
      mx += x[i];
      my += y[i];
     }
   mx /= n;
   my /= n;
   double sxy = 0, sxx = 0;
   for(int i = 0; i < n; i++)
     {
      sxy += (x[i] - mx) * (y[i] - my);
      sxx += (x[i] - mx) * (x[i] - mx);
     }
   if(sxx == 0)
      return false;
   beta = sxy / sxx;
   alpha = my - beta * mx;
   return true;
  }

#endif

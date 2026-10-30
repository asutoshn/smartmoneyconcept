//+------------------------------------------------------------------+
//|                                SMC_BOS_Confirmed_XAUUSD_EA.mq5     |
//|  Smart-Money-Concept style EA (Break-of-Structure, confirmed):    |
//|  - Detects swing-based Support/Resistance                         |
//|  - Detects Fair Value Gaps (FVG) and Order Blocks (OB)            |
//|  - Enters on a CONFIRMED S/R breakout: candle(s) must OPEN and    |
//|    CLOSE beyond the level, backed by a recent unmitigated FVG/OB  |
//|  - SL/TP: either fixed pip distances, or OB/FVG-boundary based    |
//|  - Break-even shift once trade is far enough in profit            |
//|  - Optional delayed reverse-trade after a position closes         |
//|                                                                     |
//|  FOR EDUCATIONAL / RESEARCH USE. TEST ON DEMO BEFORE LIVE USE.    |
//+------------------------------------------------------------------+
#property copyright "Educational EA"
#property version   "3.10-RiskManaged"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//================================ INPUTS ==================================
input group "=== General ==="
input int      MagicNumber          = 990011;      // Magic number
input bool     OnePositionAtATime   = true;         // Allow only one open position
input int      MaxSpreadPoints      = 500;          // Max allowed spread (points) - gold spreads are wide
input bool     ShowDashboard        = true;         // Show on-chart info panel

input group "=== Stop Loss / Take Profit ==="
input bool     UseStaticSLTP        = true;           // TRUE = fixed pip distances below. FALSE = structure(OB/FVG)-based SL with RR-ratio TP
input double   StaticSL_Points      = 2000;            // Fixed SL distance in points (broker points, i.e. price*100 for typical 2-digit XAUUSD quotes). 2000/3000 is the combo that tested well - don't let this silently drift back to a smaller default.
input double   StaticTP_Points      = 3000;            // Fixed TP distance in points

input group "=== Risk Management ==="
input double   RiskPercent          = 1.0;          // Risk per trade (% of balance). Ignored if FixedLot>0
input double   FixedLot             = 0.10;         // Fixed lot size (0 = use RiskPercent instead)
input double   RiskRewardRatio      = 2.0;          // TP distance = SL distance * this ratio
input double   ATR_BufferMultiplier = 0.5;           // Extra SL buffer = ATR * this
input int      ATR_Period           = 14;            // ATR period for buffer/volatility filter

input group "=== Structure (Support/Resistance) ==="
input int      SwingLookback        = 30;           // Bars to scan for swing high/low (structure)
input int      SwingStrength        = 3;            // Bars each side required to confirm a swing point

input group "=== Fair Value Gap / Order Block ==="
input int      FVG_LookbackBars     = 25;           // Bars to scan for unmitigated FVG
input int      OB_LookbackBars      = 25;           // Bars to scan for valid order block
input double   ImpulseBodyFactor    = 1.3;          // Impulse candle body must be > avg body * this factor
input bool     RequireBothFVGAndOB  = true;          // TRUE = need FVG *and* OB agreeing (stronger filter)

input group "=== Confirmation Filters (double confirmation) ==="
input bool     UseTrendFilter       = true;          // Only trade with the higher-timeframe trend
input int      EMA_Fast             = 50;            // Fast EMA period
input int      EMA_Slow             = 200;           // Slow EMA period
input bool     UseRSIFilter         = true;          // Require RSI momentum agreement
input int      RSI_Period           = 14;            // RSI period
input double   RSI_BullThreshold    = 50;            // Buy needs RSI above this
input double   RSI_BearThreshold    = 50;            // Sell needs RSI below this
input bool     UseVolumeFilter      = true;           // Breakout bar must show above-average volume
input double   VolumeMultiplier     = 1.2;            // Breakout bar volume must exceed avg*this
input bool     UseADXFilter         = true;           // Skip trading when market is range-bound/choppy
input int      ADX_Period           = 14;             // ADX period
input double   ADX_MinThreshold     = 20;             // Minimum ADX to consider a real trend in play
input int      ConfirmationCandles  = 2;               // Candles that must CLOSE beyond the breakout level (in a row, no pullback) before entry
input int      MaxWaitBarsForConfirmation = 6;         // Cancel the pending breakout if not confirmed within this many bars
input double   MinStopPoints        = 1500;           // Floor for SL distance in points (protects against tight stops in low ATR/range days)

input group "=== Trade Management ==="
input bool     UseTrailingStop      = true;          // Enable trailing stop once in profit
input double   TrailingStartRR      = 1.0;           // Start trailing once profit reaches this multiple of risk
input double   TrailingStepPoints   = 300;           // Trailing distance in points
input int      MaxTradesPerDay      = 5;              // Hard cap on new trades per calendar day (5 = best result found in testing so far)
input int      MinBarsBetweenTrades = 2;              // Cooldown: bars to wait after a trade before next entry (2 = best result found in testing)

input group "=== [Optional] Re-Entry Distance Guard ==="
input bool     UseReEntryDistanceGuard = false;         // Block a new entry if it's too close in price to where the last trade closed
input double   MinReEntryDistancePoints = 500;          // Minimum distance (points) required from the last close price
input bool     ReEntryDistanceSameDirectionOnly = true; // TRUE = only restrict re-entries in the SAME direction as the last trade

input group "=== [Optional] RSI Divergence Guard ==="
input bool     UseRSIDivergenceGuard = false;          // Block entry if price made a new extreme but RSI didn't confirm it
input int      RSIDivergenceLookback = 30;              // Bars to scan for the two most recent swing points
input int      RSIDivergenceSwingStrength = 2;          // Bars each side to confirm a swing point (smaller/more local than the main structure swings)

input group "=== [Optional] MACD Momentum Guard ==="
input bool     UseMACDFilter        = false;            // Require MACD to confirm trade direction, and/or block if momentum is fading
input int      MACD_FastEMA         = 12;
input int      MACD_SlowEMA         = 26;
input int      MACD_SignalPeriod    = 9;
input bool     RequireMACDCrossConfirmation = true;     // MACD line must be on the correct side of the signal line for the trade direction
input bool     BlockOnHistogramShrinking = true;        // Block if the histogram has been shrinking (momentum decelerating) for N bars
input int      MACD_HistogramShrinkBars = 3;            // Consecutive bars of shrinking histogram required to flag as "fading"

input group "=== [Optional] Trading Hours Filter ==="
input bool     UseTradingHoursFilter = true;            // Block new entries during specific server-time hours (17=best result found: $21,090.60)
input string   BlockedHours         = "17";             // Comma-separated hours (0-23, server time) to block new entries
input string   AllowedHoursOnly     = "";                // If non-empty, ONLY these hours are allowed (whitelist - overrides BlockedHours)

input group "=== [Optional] Retest Entry (wait for pullback instead of abandoning) ==="
input bool     UseRetestEntry      = false;              // If the extension filter rejects a trade, wait for price to pull back to that rejected price instead of giving up
input int      RetestMaxWaitBars   = 24;                  // Give up waiting after this many bars (24 = 2 hours on M5)

input group "=== [Optional] Breakout Extension Filter ==="
input bool     UseBreakoutExtensionFilter = false;       // Reject entry if price has already moved too far from the broken level by the time of confirmation
input double   MaxExtensionPoints   = 1000;               // Max allowed distance (points) between the broken level and the actual entry price

input group "=== [Optional] Opposite Signal Exit ==="
input bool     UseOppositeSignalExit = false;            // Close the open position if the EA's own signal engine detects a breakout in the OPPOSITE direction
input bool     OppositeSignalRequireConfirmation = false; // FALSE = one confirmation is enough (the breakout candle itself, "armed" state). TRUE = wait for the FULL multi-candle confirmation like a real entry.
input double   OppositeSignalMaxProfitPoints = 0;         // Only trigger if current floating profit is AT OR BELOW this (0 = never touch a winning trade, only breakeven/losing)
input bool     OppositeSignalCancelOnly = false;          // FALSE = close the position. TRUE = just log it, don't close (for observing behavior before trusting it)

input group "=== [Optional] Early Invalidation Exit ==="
input bool     UseInvalidationExit  = false;             // Close an open position early if price closes back through its trigger level
input int      InvalidationConfirmCandles = 1;           // Consecutive candle closes back through the level required before closing

input group "=== [Optional] Structure Break Exit (rolling N-candle low/high) ==="
input bool     UseStructureBreakExit = false;             // Exit if a candle closes beyond the low/high of the N candles before it
input int      StructureBreakLookback = 3;                // How many prior candles form the reference low/high

input group "=== [Optional] Momentum Exit (RSI reversal + optional volume confirmation) ==="
input bool     UseMomentumExit      = false;              // Exit if RSI crosses against the trade direction
input double   MomentumExitRSIBuyThreshold = 40;          // For a BUY, exit if RSI drops below this
input double   MomentumExitRSISellThreshold = 60;         // For a SELL, exit if RSI rises above this
input bool     MomentumExitRequireVolume = true;          // Only trigger if current bar's volume is also above average (real reversal, not noise)

input group "=== [Optional] EMA / Parabolic SAR Invalidation Exit ==="
input bool     UseEMAInvalidationExit = false;            // Exit if a candle closes fully past a fast EMA or PSAR flips against the trade
input bool     UseParabolicSARInstead = false;            // FALSE = fast EMA close-through mode, TRUE = Parabolic SAR flip mode
input int      EarlyExitEMA_Period   = 9;                 // Fast EMA period (only used if UseParabolicSARInstead=false)
input double   SAR_Step              = 0.02;               // Parabolic SAR step (only used if UseParabolicSARInstead=true)
input double   SAR_Maximum           = 0.2;                // Parabolic SAR maximum step

input group "=== [Optional] Multi-Timeframe Confirmation ==="
input bool     UseMultiTimeframeFilter = false;         // Require a higher timeframe's trend to agree before taking the M5 signal
input ENUM_TIMEFRAMES MTF_Timeframe = PERIOD_H1;         // Higher timeframe to check (H1 recommended - see notes)
input int      MTF_EMA_Fast         = 50;                // Fast EMA period on the higher timeframe
input int      MTF_EMA_Slow         = 200;                // Slow EMA period on the higher timeframe

input group "=== [Optional] Reversal Candle Guard ==="
input bool     UseReversalGuard     = false;           // Block entry if a recent candle shows a rejection wick against the trade direction
input int      ReversalGuardLookback = 1;               // How many recent closed candles to check (1 = just the candle before confirmation)
input double   ReversalGuardWickRatio = 0.40;            // Wick must be at least this fraction of the candle's total range (0.40 = 40%)
input double   ReversalGuardMinWickPoints = 300;         // Wick must also be at least this many points - filters out noise on tiny candles

input group "=== [Optional] Market Structure Trailing Stop (swing low/high based) ==="
input bool     UseMarketStructureTrail = false;         // Trail SL to the most recent swing low (buy) / swing high (sell) instead of a fixed point step
input int      StructureTrailSwingStrength = 2;         // Bars each side to confirm a swing point (smaller = more local/frequent updates)
input int      StructureTrailLookback = 30;              // Bars to scan for the most recent confirmed swing point
input double   StructureTrailBufferPoints = 50;          // Fixed buffer beyond the swing point (used only if UseATRDynamicBuffer=false)
input bool     UseATRDynamicBuffer = false;               // Replace the fixed buffer with a volatility-adaptive ATR-based floor
input double   ATRTrailMultiplier  = 1.5;                 // SL is never allowed closer than (ATR x this) to current price - reuses the existing 14-period ATR

input group "=== [Optional] Staged Breakeven Trail (graduated early-stage lock) ==="
input bool     UseStagedBreakevenTrail = false;         // Discrete lock steps BEFORE handing off to the normal continuous trail below
input double   Stage1_TriggerPoints = 10;               // Profit (points) needed to trigger stage 1. 0 = disabled
input double   Stage1_LockPoints    = 5;                // Points of profit to lock at stage 1 - can be LESS than the trigger (e.g. trigger=10, lock=5)
input double   Stage2_TriggerPoints = 20;               // Profit (points) needed to trigger stage 2. 0 = disabled
input double   Stage2_LockPoints    = 20;               // Points of profit to lock at stage 2
input double   Stage3_TriggerPoints = 0;                // Profit (points) needed to trigger stage 3. 0 = disabled (only 1-2 stages needed for most cases)
input double   Stage3_LockPoints    = 0;
input double   StagedTrailHandoffPoints = 2000;         // Once profit reaches this, STOP staging and hand off to the normal continuous trail (TrailingStartRR/TrailingStepPoints below). Set low (e.g. 30) for early "trail" behavior instead of more discrete stages.

input group "=== [Optional] Breakeven / Profit-Lock (ONE-TIME, does not trail further) ==="
input bool     UseBreakevenLock     = false;          // IMPORTANT: set UseTrailingStop=false above to get a pure "lock once, then leave it" behavior
input double   BreakevenTriggerPoints = 2000;          // Profit (in points) needed to trigger - 2000 = 1:1 with your 2000-pt SL
input double   LockProfitPoints     = 0;               // Points of profit to lock in at trigger. 0 = exact breakeven. E.g. 1500 = lock in 1500 pts ($15 @ 0.1 lot) instead

input group "=== [Optional] 2-Minute Hold Rule ==="
input bool     UseMinHoldTime       = false;          // Don't let trailing touch the SL until a position has been open this long
input int      MinHoldSeconds       = 120;            // Hold time in seconds (2 min default)

input group "=== [Optional] Telegram Notifications ==="
input bool     UseTelegramNotifications = false;       // Send trade open/close alerts to Telegram
input string   TelegramBotToken     = "";               // From @BotFather (e.g. "123456789:AAExample-Token")
input string   TelegramChatID       = "";               // Your chat ID or group ID (e.g. from @userinfobot)
input bool     TelegramNotifyOnOpen  = true;             // Send a message when a trade opens
input bool     TelegramNotifyOnClose = true;             // Send a message when a trade closes (with P/L)

input group "=== [Optional] News Filter (for prop firms that restrict red/high-impact news) ==="
input bool     UseNewsFilter        = false;          // OFF by default - this firm allows news trading. Flip on for firms that don't.
input bool     NewsHighImpactOnly   = true;            // TRUE = only red/high-impact events trigger the filter (ignore orange/yellow)
input string   NewsCurrencies       = "USD";            // Currency code(s) to watch, comma-separated (XAUUSD is primarily USD-driven)
input int      NewsBufferMinutesBefore = 30;            // Stop opening new trades this many minutes BEFORE a matching event
input int      NewsBufferMinutesAfter  = 30;            // Resume this many minutes AFTER the event
input bool     NewsCloseExistingPositions = false;      // Also force-close any open position when the blackout window begins

input group "=== [Optional] Friday Force-Close Filter ==="
input bool     UseFridayForceClose  = false;          // Auto-close everything before the weekend gap and stop scanning until Sunday
input int      FridayCloseHour      = 21;             // Broker SERVER time - hour to force-close (0-23)
input int      FridayCloseMinute    = 30;             // Broker SERVER time - minute to force-close
input int      SundayReopenHour     = 22;             // Broker SERVER time - hour scanning resumes on Sunday
input int      SundayReopenMinute   = 0;              // Broker SERVER time - minute scanning resumes on Sunday

input group "=== [Optional] Daily Drawdown Circuit Breaker ==="
input bool     UseDailyDrawdownLimit    = false;       // Force-close and lock out new trades if the day's loss exceeds the limit
input double   DailyDrawdownLimitPercent = 2.5;        // Realized + floating loss, as % of that day's starting equity

input group "=== [Optional] Profit-Based Position Scaling ==="
input bool     UseProfitScaling     = false;          // Lot size scales with your cushion above the static DD floor
input double   AccountStartingBalance = 100000;        // YOUR actual challenge starting balance - set this correctly, it's the fixed anchor
input double   AccountMaxDDPercent  = 1.0;             // Your prop firm's overall static max DD % (used as the scaling basis, NOT the daily breaker above)
input double   ScalingBaseLot       = 0.04;            // Lot size when your cushion equals the original DD budget (i.e. no gain/loss yet)
input double   ScalingMinLot        = 0.01;            // Hard floor - lot never scales below this
input double   ScalingMaxLot        = 0.10;            // Hard cap - lot never scales above this, however large the cushion gets

input group "=== [Optional] Direction-Change Cooldown ==="
input bool     UseDirectionChangeCooldown = true;      // Same-direction trades chain freely; switching direction requires a wait (part of best result found)
input int      DirectionChangeCooldownMinutes = 15;    // Minutes required since the last CLOSE before taking the opposite direction

input group "=== [Optional] Delayed Reverse Trade ==="
input bool     UseReverseAfterClose = false;          // After a position closes (SL or TP), open the OPPOSITE direction after a delay
input int      ReverseDelayMinutes  = 15;             // Minutes to wait after close before firing the reverse trade
input double   ReverseSL_Points     = 2000;           // SL for the reverse trade (points) - static, since original zone data is gone by then
input double   ReverseTP_Points     = 3000;           // TP for the reverse trade (points)

// NOTE: MinHoldSeconds (2-min delay) and the Delayed-Reverse-Trade feature (15-min reversal)
// are intentionally left out of this batch. Add them back in once we know which variant wins.

//================================ GLOBALS ==================================
datetime lastBarTime   = 0;
int      atrHandle     = INVALID_HANDLE;
int      emaFastHandle = INVALID_HANDLE;
int      emaSlowHandle = INVALID_HANDLE;
int      rsiHandle     = INVALID_HANDLE;
int      adxHandle     = INVALID_HANDLE;
int      macdHandle    = INVALID_HANDLE;
int      earlyExitEmaHandle = INVALID_HANDLE;
int      sarHandle     = INVALID_HANDLE;
int      mtfEmaFastHandle = INVALID_HANDLE;
int      mtfEmaSlowHandle = INVALID_HANDLE;

int      barCounter        = 0;   // increments every new bar
int      lastTradeBarIndex = -1000;
int      tradesToday       = 0;
datetime tradeDayStamp     = 0;

// --- [Optional] Direction-change cooldown: tracks the direction and close time of the last trade ---
bool     g_hasLastClosedDirection = false;
bool     g_lastClosedWasBuy       = false;
datetime g_lastCloseTime          = 0;
double   g_lastClosePrice         = 0;   // [Optional] used by the Re-Entry Distance Guard

// --- [Optional] Early Invalidation Exit: tracks the current open position's trigger level ---
double   g_openPosTriggerLevel    = 0;
bool     g_openPosIsBuy           = false;
bool     g_openPosActive          = false;

// --- [Optional] Opposite Signal Exit (confirmed tier): tracks the last FULLY CONFIRMED
// signal regardless of whether it actually opened a trade (e.g. rejected by "position
// already open"). Set at the top of TryOpenBuy/TryOpenSell, before any filter checks,
// since pendingType itself gets reset in the same tick a signal confirms.
int      g_lastConfirmedSignalBar   = -1000;

// --- [Optional] Retest Entry: waits for price to return to a previously-rejected
// (too-extended) entry price before firing, instead of abandoning the setup entirely.
bool     g_retestPending    = false;
bool     g_retestIsBuy      = false;
double   g_retestLevel      = 0;      // original broken level (kept for logging/SL reference)
double   g_retestZone       = 0;      // FVG/OB zone, needed for SL calc when it fires
double   g_retestRefPrice   = 0;      // the REJECTED entry price itself - fires once price returns to/past this
string   g_retestTag        = "";
string   g_retestZoneNote   = "";
int      g_retestStartBar   = 0;
bool     g_retestFiring     = false;  // guard: prevents re-arming a fresh wait window during a retest-triggered attempt
bool     g_lastConfirmedSignalIsBuy = false;

// --- [Optional] Daily drawdown circuit breaker ---
double   g_dayStartBalance = 0;
datetime g_ddDayStamp      = 0;
bool     g_dailyLossLockActive = false;

// --- [Optional] Friday force-close ---
bool     g_weekendCloseLogged = false;

// --- [Optional] Breakeven/profit-lock: track which position tickets already got their one-time lock ---
ulong    g_beLockedTickets[];

// --- [Optional] News filter caching (avoid querying the calendar every tick) ---
bool     g_newsCacheValid     = false;
bool     g_newsCacheResult    = false;
datetime g_newsCacheTime      = 0;
string   g_newsCacheEventName = "";

// --- [Optional] Delayed reverse trade after a position closes ---
bool     g_reverseArmed    = false;
bool     g_reverseIsBuy    = false;
datetime g_reverseArmTime  = 0;

// --- Pending breakout confirmation state machine ---
enum ENUM_PENDING_TYPE { PENDING_NONE, PENDING_BUY, PENDING_SELL };
ENUM_PENDING_TYPE pendingType        = PENDING_NONE;
double             pendingLevel      = 0;   // the S/R level that price broke
double             pendingZone       = 0;   // FVG/OB zone boundary, used for SL once confirmed
int                pendingConfirmed  = 0;   // consecutive candles that closed beyond the level so far
int                pendingStartBar   = 0;   // barCounter value when breakout was first spotted
string             pendingHasFVG_OB  = "";  // human-readable note on which structure triggered it
string             pendingTag        = "";  // short tag (FVG+OB / FVG / OB) for order comments
string             g_lastTradeReason = "No trade yet";

//+------------------------------------------------------------------+
int OnInit()
  {
   if(_Symbol != "XAUUSD" && StringFind(_Symbol,"XAU")<0)
      Print("Warning: EA tuned for XAUUSD. Running on ", _Symbol, " - verify point/pip sizing.");

   atrHandle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   if(atrHandle == INVALID_HANDLE)
     {
      Print("Failed to create ATR handle");
      return(INIT_FAILED);
     }

   emaFastHandle = iMA(_Symbol, PERIOD_CURRENT, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol, PERIOD_CURRENT, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle     = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   adxHandle     = iADX(_Symbol, PERIOD_CURRENT, ADX_Period);
   macdHandle    = iMACD(_Symbol, PERIOD_CURRENT, MACD_FastEMA, MACD_SlowEMA, MACD_SignalPeriod, PRICE_CLOSE);
   earlyExitEmaHandle = iMA(_Symbol, PERIOD_CURRENT, EarlyExitEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   sarHandle     = iSAR(_Symbol, PERIOD_CURRENT, SAR_Step, SAR_Maximum);
   mtfEmaFastHandle = iMA(_Symbol, MTF_Timeframe, MTF_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   mtfEmaSlowHandle = iMA(_Symbol, MTF_Timeframe, MTF_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   if(emaFastHandle==INVALID_HANDLE || emaSlowHandle==INVALID_HANDLE || rsiHandle==INVALID_HANDLE || adxHandle==INVALID_HANDLE || macdHandle==INVALID_HANDLE || earlyExitEmaHandle==INVALID_HANDLE || sarHandle==INVALID_HANDLE || mtfEmaFastHandle==INVALID_HANDLE || mtfEmaSlowHandle==INVALID_HANDLE)
     {
      Print("Failed to create EMA/RSI/ADX/MACD/EarlyExitEMA/SAR/MTF handle");
      return(INIT_FAILED);
     }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(atrHandle     != INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(emaFastHandle != INVALID_HANDLE) IndicatorRelease(emaFastHandle);
   if(emaSlowHandle != INVALID_HANDLE) IndicatorRelease(emaSlowHandle);
   if(rsiHandle     != INVALID_HANDLE) IndicatorRelease(rsiHandle);
   if(adxHandle     != INVALID_HANDLE) IndicatorRelease(adxHandle);
   if(macdHandle    != INVALID_HANDLE) IndicatorRelease(macdHandle);
   if(earlyExitEmaHandle != INVALID_HANDLE) IndicatorRelease(earlyExitEmaHandle);
   if(sarHandle     != INVALID_HANDLE) IndicatorRelease(sarHandle);
   if(mtfEmaFastHandle != INVALID_HANDLE) IndicatorRelease(mtfEmaFastHandle);
   if(mtfEmaSlowHandle != INVALID_HANDLE) IndicatorRelease(mtfEmaSlowHandle);
   Comment("");
  }

//+------------------------------------------------------------------+
//| [Optional] Telegram notifications via Bot API + WebRequest.      |
//| Setup required before this works:                                 |
//|  1. Create a bot via @BotFather in Telegram, get the bot token.  |
//|  2. Message the bot once, then get your chat ID (e.g. via        |
//|     @userinfobot, or the getUpdates API).                         |
//|  3. In MT5: Tools -> Options -> Expert Advisors -> tick "Allow    |
//|     WebRequest for listed URL" and add:                           |
//|     https://api.telegram.org                                      |
//|  4. Fill in TelegramBotToken and TelegramChatID inputs.           |
//| NOTE: WebRequest is generally unavailable/unreliable in Strategy  |
//| Tester - test this on demo/live, keep UseTelegramNotifications    |
//| off while backtesting.                                            |
//+------------------------------------------------------------------+
string UrlEncode(string text)
  {
   // Convert to actual UTF-8 bytes first - percent-encoding must operate on bytes,
   // not on raw UTF-16 code points (that was the bug: encoding U+274C directly as
   // "%274C" instead of its 3-byte UTF-8 form "%E2%9D%8C").
   uchar utf8[];
   StringToCharArray(text, utf8, 0, -1, CP_UTF8);
   int len = ArraySize(utf8);

   string result = "";
   for(int i = 0; i < len; i++)
     {
      uchar b = utf8[i];
      if(b == 0) continue; // trailing null terminator from StringToCharArray
      if((b>='A'&&b<='Z') || (b>='a'&&b<='z') || (b>='0'&&b<='9') || b=='-' || b=='_' || b=='.' || b=='~')
         result += CharToString(b);
      else if(b == ' ')
         result += "%20";
      else if(b == '\n')
         result += "%0A";
      else
         result += StringFormat("%%%02X", b);
     }
   return result;
  }

void SendTelegramMessage(string message)
  {
   if(!UseTelegramNotifications) return;
   if(TelegramBotToken == "" || TelegramChatID == "")
     {
      Print("[SMC EA] Telegram notification skipped - TelegramBotToken or TelegramChatID not set.");
      return;
     }

   string url = "https://api.telegram.org/bot" + TelegramBotToken + "/sendMessage";
   string postDataStr = "chat_id=" + TelegramChatID + "&text=" + UrlEncode(message);
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";

   char post[];
   StringToCharArray(postDataStr, post, 0, StringLen(postDataStr));
   char result[];
   string resultHeaders;

   ResetLastError();
   int res = WebRequest("POST", url, headers, 5000, post, result, resultHeaders);

   if(res == -1)
     {
      int err = GetLastError();
      PrintFormat("[SMC EA] Telegram send FAILED (error %d). Check that 'https://api.telegram.org' is added under Tools->Options->Expert Advisors->Allow WebRequest for listed URL.", err);
     }
   else if(res != 200)
     {
      PrintFormat("[SMC EA] Telegram send returned HTTP %d: %s", res, CharArrayToString(result));
     }
  }

//+------------------------------------------------------------------+
//| [Optional] Detect this EA's own position closes (SL or TP hit)   |
//| and arm a delayed reverse trade if UseReverseAfterClose is on.   |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber) return;
   if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;

   // The deal that CLOSES a position has the opposite type of the original position.
   // A BUY position is closed by a SELL deal, and vice versa.
   ENUM_DEAL_TYPE closingType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);

   // --- [Optional] Direction-change cooldown / re-entry distance tracking - always updated ---
   g_lastClosedWasBuy       = (closingType == DEAL_TYPE_SELL); // closed by a SELL deal -> original was BUY
   g_lastCloseTime          = TimeCurrent();
   g_lastClosePrice         = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   g_hasLastClosedDirection = true;
   g_openPosActive          = false; // [Optional] clear invalidation-exit tracking - position is gone

   // --- [Optional] Delayed reverse-trade arming - only if that feature is enabled ---
   if(UseReverseAfterClose)
     {
      g_reverseIsBuy   = (closingType == DEAL_TYPE_BUY);
      g_reverseArmed   = true;
      g_reverseArmTime = TimeCurrent();

      PrintFormat("[SMC EA] Position closed. Reverse %s trade armed, will fire in %d minute(s) if not cancelled.",
                  g_reverseIsBuy ? "BUY" : "SELL", ReverseDelayMinutes);
     }

   // --- [Optional] Telegram close notification ---
   if(TelegramNotifyOnClose)
     {
      double dealProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
      double dealPrice  = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      string originalDir = g_lastClosedWasBuy ? "BUY" : "SELL";
      string emoji = (dealProfit >= 0) ? "✅" : "❌";
      SendTelegramMessage(StringFormat("%s %s CLOSED %s\nClose Price: %.2f\nP/L: $%.2f",
                           emoji, originalDir, _Symbol, dealPrice, dealProfit));
     }
  }

//+------------------------------------------------------------------+
//| Utility: get ATR value on a given shift                          |
//+------------------------------------------------------------------+
double GetATR(int shift=1)
  {
   double buf[];
   ArraySetAsSeries(buf,true);
   if(CopyBuffer(atrHandle,0,shift,1,buf) <= 0) return 0.0;
   return buf[0];
  }

//+------------------------------------------------------------------+
//| Structure: find most recent swing high / swing low               |
//| Uses a fractal-style check: bar's high/low is extreme among      |
//| SwingStrength bars on both sides. Scans closed bars only.        |
//+------------------------------------------------------------------+
bool FindSwingHigh(const double &high[], int bars, double &level, int &barIndex)
  {
   // arrays are time-ascending (index0 = oldest); last index = most recent CLOSED bar
   int last = bars - 1; // most recent closed bar
   for(int i = last - SwingStrength; i >= SwingStrength && i >= last - SwingLookback; i--)
     {
      bool isHigh = true;
      for(int j = 1; j <= SwingStrength; j++)
        {
         if(high[i] < high[i-j] || high[i] < high[i+j]) { isHigh = false; break; }
        }
      if(isHigh)
        {
         level = high[i];
         barIndex = i;
         return true;
        }
     }
   return false;
  }

bool FindSwingLow(const double &low[], int bars, double &level, int &barIndex)
  {
   int last = bars - 1;
   for(int i = last - SwingStrength; i >= SwingStrength && i >= last - SwingLookback; i--)
     {
      bool isLow = true;
      for(int j = 1; j <= SwingStrength; j++)
        {
         if(low[i] > low[i-j] || low[i] > low[i+j]) { isLow = false; break; }
        }
      if(isLow)
        {
         level = low[i];
         barIndex = i;
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Fair Value Gap detection (3-candle imbalance)                    |
//| Bullish FVG: candle[i-2].high < candle[i].low  -> gap zone        |
//| Bearish FVG: candle[i-2].low  > candle[i].high -> gap zone        |
//| Returns most recent UNMITIGATED gap (price hasn't fully returned)|
//+------------------------------------------------------------------+
bool FindBullishFVG(const double &high[], const double &low[], const double &close[],
                     int bars, double &gapLow, double &gapHigh)
  {
   int last = bars - 1;
   int start = MathMax(2, last - FVG_LookbackBars);
   for(int i = last; i >= start; i--)
     {
      if(i-2 < 0) continue;
      if(high[i-2] < low[i])
        {
         double gLow  = high[i-2];
         double gHigh = low[i];
         // check unmitigated: no close since has fully closed back below gLow
         bool mitigated = false;
         for(int k = i+1; k <= last; k++)
           {
            if(close[k] < gLow) { mitigated = true; break; }
           }
         if(!mitigated)
           {
            gapLow = gLow; gapHigh = gHigh;
            return true;
           }
        }
     }
   return false;
  }

bool FindBearishFVG(const double &high[], const double &low[], const double &close[],
                     int bars, double &gapLow, double &gapHigh)
  {
   int last = bars - 1;
   int start = MathMax(2, last - FVG_LookbackBars);
   for(int i = last; i >= start; i--)
     {
      if(i-2 < 0) continue;
      if(low[i-2] > high[i])
        {
         double gLow  = high[i];
         double gHigh = low[i-2];
         bool mitigated = false;
         for(int k = i+1; k <= last; k++)
           {
            if(close[k] > gHigh) { mitigated = true; break; }
           }
         if(!mitigated)
           {
            gapLow = gLow; gapHigh = gHigh;
            return true;
           }
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Order Block detection                                             |
//| Bullish OB: last bearish candle immediately before a strong       |
//|             bullish impulse candle                                |
//| Bearish OB: last bullish candle immediately before a strong       |
//|             bearish impulse candle                                |
//+------------------------------------------------------------------+
double AvgBodySize(const double &open[], const double &close[], int bars, int lookback)
  {
   int last = bars - 1;
   int start = MathMax(0, last - lookback);
   double sum = 0; int cnt = 0;
   for(int i = start; i <= last; i++) { sum += MathAbs(close[i]-open[i]); cnt++; }
   return (cnt>0) ? sum/cnt : 0.0;
  }

bool FindBullishOB(const double &open[], const double &high[], const double &low[],
                    const double &close[], int bars, double &obLow, double &obHigh)
  {
   int last = bars - 1;
   double avgBody = AvgBodySize(open, close, bars, 50);
   int start = MathMax(1, last - OB_LookbackBars);
   for(int i = last; i >= start; i--)
     {
      bool impulsive = (close[i] > open[i]) && (MathAbs(close[i]-open[i]) > avgBody*ImpulseBodyFactor);
      bool prevBearish = (close[i-1] < open[i-1]);
      if(impulsive && prevBearish)
        {
         obLow  = low[i-1];
         obHigh = high[i-1];
         return true;
        }
     }
   return false;
  }

bool FindBearishOB(const double &open[], const double &high[], const double &low[],
                    const double &close[], int bars, double &obLow, double &obHigh)
  {
   int last = bars - 1;
   double avgBody = AvgBodySize(open, close, bars, 50);
   int start = MathMax(1, last - OB_LookbackBars);
   for(int i = last; i >= start; i--)
     {
      bool impulsive = (close[i] < open[i]) && (MathAbs(close[i]-open[i]) > avgBody*ImpulseBodyFactor);
      bool prevBullish = (close[i-1] > open[i-1]);
      if(impulsive && prevBullish)
        {
         obLow  = low[i-1];
         obHigh = high[i-1];
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| [Optional] Profit-based position scaling.                        |
//| Static DD floor = AccountStartingBalance * (1 - AccountMaxDDPercent/100).|
//| This floor never moves. As equity grows above the starting        |
//| balance, your cushion down to that floor grows too - so lot size  |
//| scales UP proportionally. If equity dips, cushion shrinks and lot |
//| size automatically scales DOWN, easing off as you approach the    |
//| floor. Always bounded by ScalingMinLot / ScalingMaxLot.           |
//+------------------------------------------------------------------+
double GetProfitScaledLot()
  {
   double floorEquity     = AccountStartingBalance * (1 - AccountMaxDDPercent/100.0);
   double initialCushion  = AccountStartingBalance - floorEquity;              // = starting budget, e.g. $1,000 at 1%
   double currentEquity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double currentCushion  = currentEquity - floorEquity;
   if(currentCushion < 0) currentCushion = 0;                                  // already past the floor - DD breaker should have locked trading by now

   double scaleFactor = (initialCushion > 0) ? (currentCushion / initialCushion) : 1.0;
   double lot = ScalingBaseLot * scaleFactor;
   lot = MathMax(ScalingMinLot, MathMin(ScalingMaxLot, lot));
   lot = NormalizeLot(lot);

   PrintFormat("[SMC EA] Profit-scaled lot: cushion=%.2f/%.2f (factor %.2fx) -> lot=%.2f",
               currentCushion, initialCushion, scaleFactor, lot);
   return lot;
  }

//+------------------------------------------------------------------+
//| Position sizing based on risk %                                  |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistancePrice)
  {
   if(UseProfitScaling) return GetProfitScaledLot();

   if(FixedLot > 0) return NormalizeLot(FixedLot);

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * RiskPercent / 100.0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0 || tickValue <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double lossPerLot = (slDistancePrice / tickSize) * tickValue;
   if(lossPerLot <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double lots = riskAmount / lossPerLot;
   return NormalizeLot(lots);
  }

double NormalizeLot(double lots)
  {
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots/step)*step;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return lots;
  }

//+------------------------------------------------------------------+
//| Confirmation filters                                              |
//+------------------------------------------------------------------+
bool TrendFilterOK(bool wantBuy)
  {
   if(!UseTrendFilter) return true;
   double fast[], slow[];
   ArraySetAsSeries(fast,true); ArraySetAsSeries(slow,true);
   if(CopyBuffer(emaFastHandle,0,1,1,fast) <= 0) return false;
   if(CopyBuffer(emaSlowHandle,0,1,1,slow) <= 0) return false;
   if(wantBuy)  return fast[0] > slow[0];   // uptrend: fast EMA above slow EMA
   else         return fast[0] < slow[0];   // downtrend
  }

bool RSIFilterOK(bool wantBuy)
  {
   if(!UseRSIFilter) return true;
   double rsi[];
   ArraySetAsSeries(rsi,true);
   if(CopyBuffer(rsiHandle,0,1,1,rsi) <= 0) return false;
   if(wantBuy)  return rsi[0] > RSI_BullThreshold && rsi[0] < 80; // momentum up, not extreme overbought
   else         return rsi[0] < RSI_BearThreshold && rsi[0] > 20; // momentum down, not extreme oversold
  }

double GetRSISnapshot()
  {
   double rsi[];
   ArraySetAsSeries(rsi,true);
   if(CopyBuffer(rsiHandle,0,1,1,rsi) <= 0) return 0.0;
   return rsi[0];
  }

bool GetVolumeSnapshot(double &curVol, double &avgVol)
  {
   long vol[];
   ArraySetAsSeries(vol,true);
   int need = 21;
   if(CopyTickVolume(_Symbol, PERIOD_CURRENT, 1, need, vol) < need) { curVol=0; avgVol=0; return false; }
   double avg = 0;
   for(int i=1;i<need;i++) avg += (double)vol[i];
   avg /= (need-1);
   curVol = (double)vol[0];
   avgVol = avg;
   return true;
  }

bool VolumeFilterOK()
  {
   if(!UseVolumeFilter) return true;
   double curVol, avgVol;
   if(!GetVolumeSnapshot(curVol, avgVol)) return true; // not enough data, don't block
   return (curVol > avgVol*VolumeMultiplier);
  }

bool ADXFilterOK()
  {
   if(!UseADXFilter) return true;
   double adx[];
   ArraySetAsSeries(adx,true);
   if(CopyBuffer(adxHandle,0,1,1,adx) <= 0) return true; // don't block on data failure
   return (adx[0] >= ADX_MinThreshold); // below threshold = ranging/choppy market, skip
  }

//+------------------------------------------------------------------+
//| Daily trade cap + cooldown between entries                        |
//+------------------------------------------------------------------+
void RefreshDailyCounter()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime today = StructToTime(dt);
   if(today != tradeDayStamp)
     {
      tradeDayStamp = today;
      tradesToday = 0;
     }
  }

bool TradeLimitsOK()
  {
   RefreshDailyCounter();
   if(tradesToday >= MaxTradesPerDay) return false;
   if(barCounter - lastTradeBarIndex < MinBarsBetweenTrades) return false;
   return true;
  }

// Same check as above, but tells you WHY it failed (for diagnostic logging).
// Returns "" if all limits pass.
string TradeLimitsRejectReason()
  {
   RefreshDailyCounter();
   if(tradesToday >= MaxTradesPerDay) return StringFormat("Daily trade cap reached (%d/%d)", tradesToday, MaxTradesPerDay);
   if(barCounter - lastTradeBarIndex < MinBarsBetweenTrades) return StringFormat("Cooldown active (%d/%d bars since last trade)", barCounter-lastTradeBarIndex, MinBarsBetweenTrades);
   return "";
  }

void RegisterTradeTaken()
  {
   tradesToday++;
   lastTradeBarIndex = barCounter;
  }

//+------------------------------------------------------------------+
//| Spread filter                                                     |
//+------------------------------------------------------------------+
bool SpreadOK()
  {
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spread <= MaxSpreadPoints);
  }

//+------------------------------------------------------------------+
//| Count open positions for this symbol & magic                    |
//+------------------------------------------------------------------+
int CountOpenPositions()
  {
   int cnt = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      cnt++;
     }
   return cnt;
  }

//+------------------------------------------------------------------+
//| Trailing stop management                                          |
//+------------------------------------------------------------------+
void ManageTrailing()
  {
   if(!UseTrailingStop) return;
   if(UseMarketStructureTrail) return; // mutually exclusive - structure trail handles this position's SL instead
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   // Stable, config-based risk distance - NOT the live SL distance, which would shrink
   // once the staged trail (or breakeven lock) moves the SL, causing this to trigger too early.
   double stableRiskDist = UseStaticSLTP ? (StaticSL_Points*point) : (MinStopPoints*point);

   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      long   type      = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl         = PositionGetDouble(POSITION_SL);
      double tp         = PositionGetDouble(POSITION_TP);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // [Optional] Give the trade room to breathe before any EA-driven SL adjustment
      if(UseMinHoldTime)
        {
         long openTime = (long)PositionGetInteger(POSITION_TIME);
         if(TimeCurrent() - openTime < MinHoldSeconds) continue;
        }

      // If the staged trail is active, hand off at StagedTrailHandoffPoints instead of
      // the normal risk-multiple threshold, so the two mechanisms don't overlap or conflict.
      double triggerProfit = UseStagedBreakevenTrail ? (StagedTrailHandoffPoints*point) : (stableRiskDist*TrailingStartRR);

      if(type == POSITION_TYPE_BUY)
        {
         double profit = bid - openPrice;
         if(profit >= triggerProfit)
           {
            double newSL = bid - TrailingStepPoints*point;
            if(newSL > sl && newSL < bid)
               trade.PositionModify(ticket, NormalizeDouble(newSL,_Digits), tp);
           }
        }
      else if(type == POSITION_TYPE_SELL)
        {
         double profit = openPrice - ask;
         if(profit >= triggerProfit)
           {
            double newSL = ask + TrailingStepPoints*point;
            if((sl == 0 || newSL < sl) && newSL > ask)
               trade.PositionModify(ticket, NormalizeDouble(newSL,_Digits), tp);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| [Optional] Market Structure Trailing Stop.                         |
//| Instead of a fixed point step, trails the SL to the most recent    |
//| CONFIRMED swing low (buy) or swing high (sell) - standard          |
//| institutional/discretionary practice: the stop follows structure,  |
//| not an arbitrary distance. Only ever moves in the favorable        |
//| direction (never loosens). Mutually exclusive with the fixed-step  |
//| continuous trail (ManageTrailing yields when this is enabled).     |
//+------------------------------------------------------------------+
void ManageMarketStructureTrail()
  {
   if(!UseMarketStructureTrail) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int s = StructureTrailSwingStrength;
   int need = StructureTrailLookback + 2*s;

   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, need, high) < need) return;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 1, need, low) < need) return;

   // ATR-based buffer/floor: reuses the same 14-period ATR (ATR_Period input) already
   // computed elsewhere in the EA. If UseATRDynamicBuffer is on, this REPLACES the fixed
   // StructureTrailBufferPoints buffer entirely, and ALSO enforces a hard floor - the SL
   // is never allowed closer than (ATR x ATRTrailMultiplier) to current price, regardless
   // of how close the swing point itself is. This adapts to volatility instead of using a
   // one-size-fits-all fixed distance.
   double atrValue = 0;
   double minDistFromPrice = 0;
   if(UseATRDynamicBuffer)
     {
      atrValue = GetATR();
      minDistFromPrice = atrValue * ATRTrailMultiplier;
     }

   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      if(UseMinHoldTime)
        {
         long openTime = (long)PositionGetInteger(POSITION_TIME);
         if(TimeCurrent() - openTime < MinHoldSeconds) continue;
        }

      long   type = PositionGetInteger(POSITION_TYPE);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(type == POSITION_TYPE_BUY)
        {
         // Most recent CONFIRMED swing low: needs s newer bars (smaller index) and
         // s older bars (larger index) on either side, none of which undercut it.
         double swingLow = 0; bool found = false;
         for(int j = s; j < need - s && j < StructureTrailLookback; j++)
           {
            bool isLow = true;
            for(int k = 1; k <= s; k++)
               if(low[j] > low[j-k] || low[j] > low[j+k]) { isLow = false; break; }
            if(isLow) { swingLow = low[j]; found = true; break; }
           }
         if(!found) continue;

         double buffer = UseATRDynamicBuffer ? atrValue : (StructureTrailBufferPoints*point);
         double newSL = swingLow - buffer;

         if(UseATRDynamicBuffer)
           {
            // Enforce the floor: never let the SL sit closer than minDistFromPrice to bid,
            // even if the swing low itself is closer than that.
            double floorSL = bid - minDistFromPrice;
            if(newSL > floorSL) newSL = floorSL;
           }

         if(newSL > sl && newSL < bid)
           {
            trade.PositionModify(ticket, NormalizeDouble(newSL,_Digits), tp);
            PrintFormat("[SMC EA] Market structure trail (BUY #%d): SL -> %.2f (below swing low %.2f, buffer=%.2f%s)",
                        ticket, newSL, swingLow, buffer, UseATRDynamicBuffer ? " [ATR]" : "");
           }
        }
      else if(type == POSITION_TYPE_SELL)
        {
         double swingHigh = 0; bool found = false;
         for(int j = s; j < need - s && j < StructureTrailLookback; j++)
           {
            bool isHigh = true;
            for(int k = 1; k <= s; k++)
               if(high[j] < high[j-k] || high[j] < high[j+k]) { isHigh = false; break; }
            if(isHigh) { swingHigh = high[j]; found = true; break; }
           }
         if(!found) continue;

         double buffer = UseATRDynamicBuffer ? atrValue : (StructureTrailBufferPoints*point);
         double newSL = swingHigh + buffer;

         if(UseATRDynamicBuffer)
           {
            double floorSL = ask + minDistFromPrice;
            if(newSL < floorSL) newSL = floorSL;
           }

         if((sl == 0 || newSL < sl) && newSL > ask)
           {
            trade.PositionModify(ticket, NormalizeDouble(newSL,_Digits), tp);
            PrintFormat("[SMC EA] Market structure trail (SELL #%d): SL -> %.2f (above swing high %.2f, buffer=%.2f%s)",
                        ticket, newSL, swingHigh, buffer, UseATRDynamicBuffer ? " [ATR]" : "");
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| [Optional] Staged Breakeven Trail.                                 |
//| Below StagedTrailHandoffPoints of profit, moves the SL in DISCRETE |
//| steps as each stage's trigger is reached, locking that stage's     |
//| specified profit amount (which can be less than, equal to, or      |
//| more calibrated than the trigger itself - e.g. trigger=10,         |
//| lock=5). Holds steady between stages (no continuous creep).        |
//| Once profit reaches StagedTrailHandoffPoints, this stops acting    |
//| and ManageTrailing's normal continuous trail takes over from       |
//| wherever this left the SL.                                         |
//+------------------------------------------------------------------+
bool GetStagedLockPoints(double profitPoints, double &lockOut)
  {
   bool found = false;
   if(Stage1_TriggerPoints > 0 && profitPoints >= Stage1_TriggerPoints) { lockOut = Stage1_LockPoints; found = true; }
   if(Stage2_TriggerPoints > 0 && profitPoints >= Stage2_TriggerPoints) { lockOut = Stage2_LockPoints; found = true; }
   if(Stage3_TriggerPoints > 0 && profitPoints >= Stage3_TriggerPoints) { lockOut = Stage3_LockPoints; found = true; }
   return found;
  }

void ManageStagedBreakevenTrail()
  {
   if(!UseStagedBreakevenTrail) return;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      if(UseMinHoldTime)
        {
         long openTime = (long)PositionGetInteger(POSITION_TIME);
         if(TimeCurrent() - openTime < MinHoldSeconds) continue;
        }

      long   type      = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl        = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double profitPoints;
      if(type == POSITION_TYPE_BUY)       profitPoints = (bid - openPrice) / point;
      else if(type == POSITION_TYPE_SELL) profitPoints = (openPrice - ask) / point;
      else continue;

      if(profitPoints >= StagedTrailHandoffPoints) continue; // handed off to the normal continuous trail already

      double lockPoints;
      if(!GetStagedLockPoints(profitPoints, lockPoints)) continue; // no stage reached yet

      if(type == POSITION_TYPE_BUY)
        {
         double newSL = openPrice + lockPoints*point;
         if(newSL > sl && newSL < bid)
           {
            trade.PositionModify(ticket, NormalizeDouble(newSL,_Digits), tp);
            PrintFormat("[SMC EA] Staged trail (BUY #%d): profit=%.0fpts -> SL locked at +%.0fpts (%.2f)",
                        ticket, profitPoints, lockPoints, newSL);
           }
        }
      else
        {
         double newSL = openPrice - lockPoints*point;
         if((sl == 0 || newSL < sl) && newSL > ask)
           {
            trade.PositionModify(ticket, NormalizeDouble(newSL,_Digits), tp);
            PrintFormat("[SMC EA] Staged trail (SELL #%d): profit=%.0fpts -> SL locked at +%.0fpts (%.2f)",
                        ticket, profitPoints, lockPoints, newSL);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| [Optional] Breakeven / profit-lock. ONE-TIME action: once profit  |
//| reaches BreakevenTriggerPoints, move SL to lock in exactly         |
//| LockProfitPoints of profit (0 = exact breakeven), then STOP -      |
//| does not touch that SL again. Pair with UseTrailingStop=false      |
//| for a pure "lock once, then let it run untouched to TP" behavior. |
//+------------------------------------------------------------------+
bool TicketAlreadyBELocked(ulong ticket)
  {
   for(int i = 0; i < ArraySize(g_beLockedTickets); i++)
      if(g_beLockedTickets[i] == ticket) return true;
   return false;
  }

void MarkTicketBELocked(ulong ticket)
  {
   int n = ArraySize(g_beLockedTickets);
   ArrayResize(g_beLockedTickets, n+1);
   g_beLockedTickets[n] = ticket;
  }

void ManageBreakevenLock()
  {
   if(!UseBreakevenLock) return;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(TicketAlreadyBELocked(ticket)) continue;

      long   type      = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double tp        = PositionGetDouble(POSITION_TP);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(type == POSITION_TYPE_BUY)
        {
         double profit = bid - openPrice;
         if(profit >= BreakevenTriggerPoints*point)
           {
            double newSL = openPrice + LockProfitPoints*point; // directly relative to entry - no addition math needed
            if(newSL < bid)
              {
               trade.PositionModify(ticket, NormalizeDouble(newSL,_Digits), tp);
               MarkTicketBELocked(ticket);
               PrintFormat("[SMC EA] Breakeven/profit-lock applied (BUY #%d): SL fixed at %.2f (locking %.0f pts). Will NOT trail further.",
                           ticket, newSL, LockProfitPoints);
              }
           }
        }
      else if(type == POSITION_TYPE_SELL)
        {
         double profit = openPrice - ask;
         if(profit >= BreakevenTriggerPoints*point)
           {
            double newSL = openPrice - LockProfitPoints*point;
            if(newSL > ask)
              {
               trade.PositionModify(ticket, NormalizeDouble(newSL,_Digits), tp);
               MarkTicketBELocked(ticket);
               PrintFormat("[SMC EA] Breakeven/profit-lock applied (SELL #%d): SL fixed at %.2f (locking %.0f pts). Will NOT trail further.",
                           ticket, newSL, LockProfitPoints);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Shared helper: close every open position and delete every        |
//| pending order for this symbol/magic. Used by the Friday filter    |
//| and the daily drawdown circuit breaker.                           |
//+------------------------------------------------------------------+
void CloseAllPositionsAndOrders(string reason)
  {
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(trade.PositionClose(ticket))
         PrintFormat("[SMC EA] Position #%d force-closed. Reason: %s", ticket, reason);
     }

   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket <= 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if(trade.OrderDelete(ticket))
         PrintFormat("[SMC EA] Pending order #%d deleted. Reason: %s", ticket, reason);
     }

   // Drop any in-flight breakout confirmation so it doesn't carry into the next session
   pendingType = PENDING_NONE;
   // Also cancel any armed reverse trade - a fresh circuit-breaker or weekend close overrides it
   g_reverseArmed = false;
  }

//+------------------------------------------------------------------+
//| [Optional] Friday force-close: flat everything before the        |
//| weekend gap, stay out of the market until Sunday reopen.         |
//+------------------------------------------------------------------+
bool IsWeekendCloseWindow()
  {
   if(!UseFridayForceClose) return false;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int dow = dt.day_of_week; // 0=Sunday .. 5=Friday .. 6=Saturday
   int minutesNow = dt.hour*60 + dt.min;
   int fridayCutoff = FridayCloseHour*60 + FridayCloseMinute;
   int sundayReopen = SundayReopenHour*60 + SundayReopenMinute;

   if(dow == 5 && minutesNow >= fridayCutoff) return true; // Friday evening onward
   if(dow == 6) return true;                                // all Saturday
   if(dow == 0 && minutesNow < sundayReopen) return true;   // Sunday before reopen
   return false;
  }

void ManageFridayForceClose()
  {
   if(!UseFridayForceClose) return;

   if(IsWeekendCloseWindow())
     {
      if(!g_weekendCloseLogged)
        {
         PrintFormat("[SMC EA] Weekend close window reached (server time %s). Flattening and pausing until Sunday %02d:%02d.",
                     TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), SundayReopenHour, SundayReopenMinute);
         CloseAllPositionsAndOrders("Friday weekend force-close");
         g_weekendCloseLogged = true;
        }
     }
   else
     {
      g_weekendCloseLogged = false; // reset so next Friday logs again
     }
  }

//+------------------------------------------------------------------+
//| [Optional] News filter - uses MT5's built-in Economic Calendar.  |
//| Blocks NEW entries within NewsBufferMinutesBefore/After of a     |
//| matching event. Results are cached briefly since calendar        |
//| queries don't need to run every single tick.                     |
//+------------------------------------------------------------------+
bool IsNewsBlackoutWindow()
  {
   if(!UseNewsFilter) return false;

   // Cache for 30 seconds - the blackout window doesn't need tick-level precision
   if(g_newsCacheValid && (TimeCurrent() - g_newsCacheTime) < 30)
      return g_newsCacheResult;

   g_newsCacheTime  = TimeCurrent();
   g_newsCacheValid = true;
   g_newsCacheResult = false;
   g_newsCacheEventName = "";

   datetime now        = TimeCurrent();
   datetime rangeFrom   = now - 86400; // look back 1 day
   datetime rangeTo     = now + 86400; // look ahead 1 day

   MqlCalendarValue values[];

   // Split NewsCurrencies on commas and query each one (CalendarValueHistory takes a single currency code)
   string currencies[];
   int nCur = StringSplit(NewsCurrencies, ',', currencies);
   if(nCur <= 0) { nCur = 1; ArrayResize(currencies,1); currencies[0] = NewsCurrencies; }

   for(int c = 0; c < nCur; c++)
     {
      string curCode = currencies[c];
      StringTrimLeft(curCode);
      StringTrimRight(curCode);
      if(curCode == "") continue;

      int total = CalendarValueHistory(values, rangeFrom, rangeTo, NULL, curCode);
      if(total <= 0) continue;

      for(int i = 0; i < total; i++)
        {
         MqlCalendarEvent event;
         if(!CalendarEventById(values[i].event_id, event)) continue;

         if(NewsHighImpactOnly && event.importance != CALENDAR_IMPORTANCE_HIGH) continue;
         if(!NewsHighImpactOnly && event.importance == CALENDAR_IMPORTANCE_NONE) continue;

         datetime eventTime     = values[i].time;
         datetime blackoutStart = eventTime - NewsBufferMinutesBefore*60;
         datetime blackoutEnd   = eventTime + NewsBufferMinutesAfter*60;

         if(now >= blackoutStart && now <= blackoutEnd)
           {
            g_newsCacheResult    = true;
            g_newsCacheEventName = StringFormat("%s (%s) at %s", event.name, curCode, TimeToString(eventTime, TIME_DATE|TIME_MINUTES));
            break;
           }
        }
      if(g_newsCacheResult) break;
     }

   return g_newsCacheResult;
  }

void ManageNewsFilter()
  {
   if(!UseNewsFilter) return;
   if(!NewsCloseExistingPositions) return; // nothing to actively manage - TryOpenBuy/Sell already gate new entries

   if(IsNewsBlackoutWindow() && CountOpenPositions() > 0)
     {
      PrintFormat("[SMC EA] News blackout active (%s) - closing existing position(s) per NewsCloseExistingPositions.",
                  g_newsCacheEventName);
      CloseAllPositionsAndOrders(StringFormat("News blackout: %s", g_newsCacheEventName));
     }
  }

//+------------------------------------------------------------------+
//| [Optional] Daily drawdown circuit breaker.                       |
//+------------------------------------------------------------------+
void RefreshDailyEquityBaseline()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime today = StructToTime(dt);
   if(today != g_ddDayStamp)
     {
      g_ddDayStamp      = today;
      g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_dailyLossLockActive = false; // new day - lift yesterday's lock
      PrintFormat("[SMC EA] New trading day. Starting balance baseline = %.2f", g_dayStartBalance);
     }
  }

bool DailyDrawdownLockActive()
  {
   if(!UseDailyDrawdownLimit) return false;
   RefreshDailyEquityBaseline();
   return g_dailyLossLockActive;
  }

void ManageDailyDrawdownCircuitBreaker()
  {
   if(!UseDailyDrawdownLimit) return;
   RefreshDailyEquityBaseline();
   if(g_dailyLossLockActive) return;     // already tripped today, nothing more to do
   if(g_dayStartBalance <= 0) return;    // not initialized yet

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double lossPercent = (g_dayStartBalance - equity) / g_dayStartBalance * 100.0;

   if(lossPercent >= DailyDrawdownLimitPercent)
     {
      PrintFormat("[SMC EA] DAILY DRAWDOWN LIMIT HIT: %.2f%% loss (limit %.2f%%). Flattening and locking out new trades until midnight server time.",
                  lossPercent, DailyDrawdownLimitPercent);
      CloseAllPositionsAndOrders(StringFormat("Daily drawdown limit hit (%.2f%%)", lossPercent));
      g_dailyLossLockActive = true;
     }
  }

//+------------------------------------------------------------------+
//| [Optional] Fire the delayed reverse trade once ReverseDelayMinutes|
//| has elapsed since the previous position closed. Uses static       |
//| SL/TP since the original OB/FVG zone no longer applies then.      |
//+------------------------------------------------------------------+
void ManageReverseTrade()
  {
   if(!UseReverseAfterClose) return;
   if(!g_reverseArmed) return;
   if(TimeCurrent() - g_reverseArmTime < ReverseDelayMinutes*60) return;

   g_reverseArmed = false; // consume the signal regardless of outcome below

   if(IsWeekendCloseWindow()) return;
   if(DailyDrawdownLockActive()) return;
   if(OnePositionAtATime && CountOpenPositions() > 0) return;
   if(!SpreadOK()) return;
   if(TradeLimitsRejectReason() != "") return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(g_reverseIsBuy)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = ask - ReverseSL_Points*point;
      double tp  = ask + ReverseTP_Points*point;
      if(trade.Buy(CalculateLotSize(ReverseSL_Points*point), _Symbol, ask,
                   NormalizeDouble(sl,_Digits), NormalizeDouble(tp,_Digits), "SMC Reverse Buy"))
        {
         RegisterTradeTaken();
         g_lastTradeReason = StringFormat("BUY (delayed reverse) | Entry=%.2f SL=%.2f TP=%.2f", ask, sl, tp);
         PrintFormat("[SMC EA] TRADE OPENED - %s", g_lastTradeReason);
         if(TelegramNotifyOnOpen)
            SendTelegramMessage(StringFormat("🔁 BUY (reverse) %s\nEntry: %.2f\nSL: %.2f\nTP: %.2f", _Symbol, ask, sl, tp));
        }
     }
   else
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = bid + ReverseSL_Points*point;
      double tp  = bid - ReverseTP_Points*point;
      if(trade.Sell(CalculateLotSize(ReverseSL_Points*point), _Symbol, bid,
                    NormalizeDouble(sl,_Digits), NormalizeDouble(tp,_Digits), "SMC Reverse Sell"))
        {
         RegisterTradeTaken();
         g_lastTradeReason = StringFormat("SELL (delayed reverse) | Entry=%.2f SL=%.2f TP=%.2f", bid, sl, tp);
         PrintFormat("[SMC EA] TRADE OPENED - %s", g_lastTradeReason);
         if(TelegramNotifyOnOpen)
            SendTelegramMessage(StringFormat("🔁 SELL (reverse) %s\nEntry: %.2f\nSL: %.2f\nTP: %.2f", _Symbol, bid, sl, tp));
        }
     }
  }

//+------------------------------------------------------------------+
//| [Optional] Direction-change cooldown.                            |
//| Same direction as the last trade -> no extra wait (chains freely,|
//| still subject to the normal MinBarsBetweenTrades cooldown).      |
//| Opposite direction -> must wait DirectionChangeCooldownMinutes    |
//| since the last trade CLOSED.                                      |
//+------------------------------------------------------------------+
bool DirectionChangeCooldownOK(bool wantBuy)
  {
   if(!UseDirectionChangeCooldown) return true;
   if(!g_hasLastClosedDirection) return true;
   if(wantBuy == g_lastClosedWasBuy) return true;
   return (TimeCurrent() - g_lastCloseTime) >= DirectionChangeCooldownMinutes*60;
  }

//+------------------------------------------------------------------+
//| [Optional] Trading Hours Filter.                                   |
//| BlockedHours: comma-separated server-time hours (0-23) that never |
//| take new entries. AllowedHoursOnly (if non-empty) is a whitelist   |
//| that overrides BlockedHours entirely - only those hours trade.     |
//+------------------------------------------------------------------+
bool HourInList(int hour, string csv)
  {
   if(csv == "") return false;
   string parts[];
   int n = StringSplit(csv, ',', parts);
   for(int i = 0; i < n; i++)
     {
      string p = parts[i];
      StringTrimLeft(p);
      StringTrimRight(p);
      if(p == "") continue;
      if((int)StringToInteger(p) == hour) return true;
     }
   return false;
  }

bool TradingHoursFilterOK()
  {
   if(!UseTradingHoursFilter) return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;

   if(AllowedHoursOnly != "")
      return HourInList(hour, AllowedHoursOnly); // whitelist mode - only listed hours pass

   if(BlockedHours != "" && HourInList(hour, BlockedHours))
      return false; // blacklist mode - listed hours are blocked

   return true;
  }

//+------------------------------------------------------------------+
//| [Optional] Early Invalidation Exit.                                |
//| Closes the open position immediately - regardless of current P/L -|
//| if price closes back through the level whose breakout justified   |
//| the trade, for InvalidationConfirmCandles consecutive candles.     |
//| Runs once per new bar (candle-close based, not tick-based).       |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Shared helper for ALL early-exit mechanisms below. Respects       |
//| UseMinHoldTime consistently (previously the invalidation exit did |
//| NOT check this - fixed here so every early-exit mechanism honors  |
//| the same hold-time rule as the rest of the EA's trade management).|
//+------------------------------------------------------------------+
void CloseEarlyExit(string reason)
  {
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      if(UseMinHoldTime)
        {
         long openTime = (long)PositionGetInteger(POSITION_TIME);
         if(TimeCurrent() - openTime < MinHoldSeconds) continue; // still within the hold window - leave it alone
        }

      double profit = PositionGetDouble(POSITION_PROFIT);
      if(trade.PositionClose(ticket))
        {
         PrintFormat("[SMC EA] EARLY EXIT: closed #%d - %s. P/L at close: %.2f", ticket, reason, profit);
         g_openPosActive = false;
        }
     }
  }

void ManageInvalidationExit()
  {
   if(!UseInvalidationExit) return;
   if(!g_openPosActive) return;
   if(CountOpenPositions() == 0) { g_openPosActive = false; return; }

   double close[];
   ArraySetAsSeries(close, true);
   int need = InvalidationConfirmCandles;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 1, need, close) < need) return;

   bool invalidated = true;
   for(int i = 0; i < need; i++)
     {
      if(g_openPosIsBuy)
        {
         if(close[i] >= g_openPosTriggerLevel) { invalidated = false; break; }
        }
      else
        {
         if(close[i] <= g_openPosTriggerLevel) { invalidated = false; break; }
        }
     }
   if(!invalidated) return;

   CloseEarlyExit(StringFormat("structural invalidation - closed back through trigger level %.2f for %d candle(s)",
                                g_openPosTriggerLevel, InvalidationConfirmCandles));
  }

//+------------------------------------------------------------------+
//| [Optional] Opposite Signal Exit.                                   |
//| The EA's own breakout-confirmation engine keeps watching setups     |
//| even while a position is already open (it just can't act on them   |
//| due to OnePositionAtATime). This uses that live state to exit      |
//| early rather than wait for the fixed SL - but only:                |
//|  1. If OppositeSignalRequireConfirmation=true, only a FULLY        |
//|     CONFIRMED opposite signal counts (both candles) - tracked via  |
//|     g_lastConfirmedSignalBar, since pendingType itself resets in   |
//|     the same tick a signal confirms. FALSE = the weaker "armed"    |
//|     stage (first candle only) is enough.                           |
//|  2. Only if current floating profit is at/below                    |
//|     OppositeSignalMaxProfitPoints - never touches a trade that's   |
//|     still meaningfully winning, since it may well pull back to     |
//|     profit on its own even after an opposite signal appears.       |
//| OppositeSignalCancelOnly=true logs what WOULD happen without       |
//| actually closing anything.                                         |
//+------------------------------------------------------------------+
void ManageOppositeSignalExit()
  {
   if(!UseOppositeSignalExit) return;
   if(!g_openPosActive) return;
   if(CountOpenPositions() == 0) { g_openPosActive = false; return; }

   // --- P&L gate: only act when NOT meaningfully winning ---
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double openPrice = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      break; // OnePositionAtATime - only one relevant position
     }
   if(openPrice <= 0) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double curProfitPoints = g_openPosIsBuy ? (bid-openPrice)/point : (openPrice-ask)/point;

   if(curProfitPoints > OppositeSignalMaxProfitPoints)
      return; // still winning beyond the allowed threshold - leave it alone, it may recover on its own

   // --- Opposite signal detection: confirmed tier or armed tier ---
   bool oppositeDetected = false;
   string detail = "";

   if(OppositeSignalRequireConfirmation)
     {
      bool freshConfirmed = (barCounter - g_lastConfirmedSignalBar) <= 1;
      if(g_openPosIsBuy && freshConfirmed && !g_lastConfirmedSignalIsBuy)
        {
         oppositeDetected = true;
         detail = StringFormat("opposite SELL signal FULLY CONFIRMED (profit=%.0fpts)", curProfitPoints);
        }
      else if(!g_openPosIsBuy && freshConfirmed && g_lastConfirmedSignalIsBuy)
        {
         oppositeDetected = true;
         detail = StringFormat("opposite BUY signal FULLY CONFIRMED (profit=%.0fpts)", curProfitPoints);
        }
     }
   else
     {
      if(g_openPosIsBuy && pendingType == PENDING_SELL)
        {
         oppositeDetected = true;
         detail = StringFormat("opposite SELL breakout armed at support=%.2f (profit=%.0fpts)", pendingLevel, curProfitPoints);
        }
      else if(!g_openPosIsBuy && pendingType == PENDING_BUY)
        {
         oppositeDetected = true;
         detail = StringFormat("opposite BUY breakout armed at resistance=%.2f (profit=%.0fpts)", pendingLevel, curProfitPoints);
        }
     }
   if(!oppositeDetected) return;

   if(OppositeSignalCancelOnly)
     {
      PrintFormat("[SMC EA] OPPOSITE SIGNAL DETECTED (observe-only, not closing): %s", detail);
      return;
     }

   CloseEarlyExit(StringFormat("opposite signal exit - %s", detail));
  }

//+------------------------------------------------------------------+
//| [Optional] Structure Break Exit.                                   |
//| Reference = the low (for a BUY) or high (for a SELL) of the       |
//| StructureBreakLookback candles immediately before the confirming   |
//| candle. If the confirming candle's CLOSE breaks past that          |
//| reference, exit immediately - catches micro-structure failure     |
//| well before the full SL distance is reached.                      |
//+------------------------------------------------------------------+
void ManageStructureBreakExit()
  {
   if(!UseStructureBreakExit) return;
   if(!g_openPosActive) return;
   if(CountOpenPositions() == 0) { g_openPosActive = false; return; }

   double low[], high[], close[];
   ArraySetAsSeries(low,true); ArraySetAsSeries(high,true); ArraySetAsSeries(close,true);
   int need = StructureBreakLookback + 1; // +1 for the confirming candle itself
   if(CopyLow(_Symbol, PERIOD_CURRENT, 1, need, low) < need) return;
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, need, high) < need) return;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 1, need, close) < need) return;

   // index 0 = the just-closed confirming candle; indices 1..N = the reference window before it
   if(g_openPosIsBuy)
     {
      double refLow = low[1];
      for(int i = 2; i <= StructureBreakLookback; i++) refLow = MathMin(refLow, low[i]);
      if(close[0] < refLow)
         CloseEarlyExit(StringFormat("structure break (buy): close=%.2f below %d-candle low=%.2f",
                                      close[0], StructureBreakLookback, refLow));
     }
   else
     {
      double refHigh = high[1];
      for(int i = 2; i <= StructureBreakLookback; i++) refHigh = MathMax(refHigh, high[i]);
      if(close[0] > refHigh)
         CloseEarlyExit(StringFormat("structure break (sell): close=%.2f above %d-candle high=%.2f",
                                      close[0], StructureBreakLookback, refHigh));
     }
  }

//+------------------------------------------------------------------+
//| [Optional] Momentum Exit.                                          |
//| Exits if RSI crosses against the trade direction, optionally       |
//| requiring the current bar's volume to also be above average       |
//| (distinguishing a real reversal from low-volume noise).            |
//+------------------------------------------------------------------+
void ManageMomentumExit()
  {
   if(!UseMomentumExit) return;
   if(!g_openPosActive) return;
   if(CountOpenPositions() == 0) { g_openPosActive = false; return; }

   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(rsiHandle, 0, 1, 1, rsi) < 1) return;

   bool rsiTriggered = false;
   if(g_openPosIsBuy  && rsi[0] < MomentumExitRSIBuyThreshold)  rsiTriggered = true;
   if(!g_openPosIsBuy && rsi[0] > MomentumExitRSISellThreshold) rsiTriggered = true;
   if(!rsiTriggered) return;

   if(MomentumExitRequireVolume)
     {
      double curVol, avgVol;
      if(GetVolumeSnapshot(curVol, avgVol) && curVol <= avgVol)
         return; // RSI flipped but on below-average volume - treat as noise, don't exit
     }

   CloseEarlyExit(StringFormat("momentum exit: RSI=%.1f crossed against %s", rsi[0], g_openPosIsBuy ? "BUY" : "SELL"));
  }

//+------------------------------------------------------------------+
//| [Optional] EMA / Parabolic SAR Invalidation Exit.                  |
//| Either mode: a fast EMA close-through, or a Parabolic SAR flip     |
//| against the trade direction.                                       |
//+------------------------------------------------------------------+
void ManageEMAInvalidationExit()
  {
   if(!UseEMAInvalidationExit) return;
   if(!g_openPosActive) return;
   if(CountOpenPositions() == 0) { g_openPosActive = false; return; }

   double close[];
   ArraySetAsSeries(close, true);
   if(CopyClose(_Symbol, PERIOD_CURRENT, 1, 1, close) < 1) return;

   if(UseParabolicSARInstead)
     {
      double sar[];
      ArraySetAsSeries(sar, true);
      if(CopyBuffer(sarHandle, 0, 1, 1, sar) < 1) return;

      if(g_openPosIsBuy && sar[0] > close[0])
         CloseEarlyExit(StringFormat("PSAR flip (buy): SAR=%.2f above close=%.2f", sar[0], close[0]));
      else if(!g_openPosIsBuy && sar[0] < close[0])
         CloseEarlyExit(StringFormat("PSAR flip (sell): SAR=%.2f below close=%.2f", sar[0], close[0]));
     }
   else
     {
      double ema[];
      ArraySetAsSeries(ema, true);
      if(CopyBuffer(earlyExitEmaHandle, 0, 1, 1, ema) < 1) return;

      if(g_openPosIsBuy && close[0] < ema[0])
         CloseEarlyExit(StringFormat("EMA%d invalidation (buy): close=%.2f below EMA=%.2f", EarlyExitEMA_Period, close[0], ema[0]));
      else if(!g_openPosIsBuy && close[0] > ema[0])
         CloseEarlyExit(StringFormat("EMA%d invalidation (sell): close=%.2f above EMA=%.2f", EarlyExitEMA_Period, close[0], ema[0]));
     }
  }

//+------------------------------------------------------------------+
//| [Optional] Reversal Candle Guard.                                  |
//| Before allowing entry, checks the most recent closed candle(s)    |
//| for a rejection wick AGAINST the trade direction:                  |
//|  - For a SELL: a long LOWER wick (buyers rejected the lows) means  |
//|    the down-move may already be exhausted -> block the sell.       |
//|  - For a BUY: a long UPPER wick (sellers rejected the highs) means |
//|    the up-move may already be exhausted -> block the buy.          |
//| This is exactly the pattern that hurt the trade on 2026.07.16      |
//| 16:10 - a rejection candle at 16:05 preceded a SELL entry that     |
//| got run over by the reversal it was already signaling.             |
//+------------------------------------------------------------------+
bool ReversalGuardOK(bool wantBuy)
  {
   if(!UseReversalGuard) return true;

   double o[], h[], l[], c[];
   ArraySetAsSeries(o,true); ArraySetAsSeries(h,true); ArraySetAsSeries(l,true); ArraySetAsSeries(c,true);
   int need = ReversalGuardLookback;
   if(CopyOpen(_Symbol, PERIOD_CURRENT, 1, need, o) < need) return true;  // not enough data, don't block
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, need, h) < need) return true;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 1, need, l) < need) return true;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 1, need, c) < need) return true;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = 0; i < need; i++)
     {
      double range = h[i] - l[i];
      if(range <= 0) continue;

      double lowerWick = MathMin(o[i],c[i]) - l[i];
      double upperWick = h[i] - MathMax(o[i],c[i]);

      if(wantBuy)
        {
         if(upperWick >= ReversalGuardMinWickPoints*point && (upperWick/range) >= ReversalGuardWickRatio)
           {
            PrintFormat("[SMC EA] Reversal guard: bearish rejection wick %d bar(s) back (upper=%.0fpts, %.0f%% of range) - blocking BUY",
                        i+1, upperWick/point, upperWick/range*100);
            return false;
           }
        }
      else
        {
         if(lowerWick >= ReversalGuardMinWickPoints*point && (lowerWick/range) >= ReversalGuardWickRatio)
           {
            PrintFormat("[SMC EA] Reversal guard: bullish rejection wick %d bar(s) back (lower=%.0fpts, %.0f%% of range) - blocking SELL",
                        i+1, lowerWick/point, lowerWick/range*100);
            return false;
           }
        }
     }
   return true;
  }

//+------------------------------------------------------------------+
//| [Optional] Re-Entry Distance Guard - DIRECTIONAL.                  |
//| Blocks a new entry only if it's on the ADVERSE side of where the  |
//| last trade closed (price bounced back against the direction)      |
//| and hasn't moved far enough away yet. A new entry on the          |
//| FAVORABLE side (genuine continuation past the last close) is      |
//| allowed immediately, regardless of distance - that reflects real  |
//| momentum, not "chasing the same level."                            |
//|                                                                     |
//| SELL: adverse side = new entry ABOVE the last close (price         |
//|       bounced up before re-shorting). Below/equal = continuation, |
//|       always allowed.                                              |
//| BUY:  adverse side = new entry BELOW the last close (price         |
//|       pulled back before re-buying). Above/equal = continuation,  |
//|       always allowed.                                              |
//|                                                                     |
//| This is the pattern from 2026.07.16: trade 2 (SELL) closed at      |
//| 3979.84, trade 3 (SELL) opened at 3983.81 - ABOVE the last close,  |
//| the adverse/bounce side, only ~397 points away.                    |
//+------------------------------------------------------------------+
bool ReEntryDistanceOK(bool wantBuy, double proposedEntryPrice)
  {
   if(!UseReEntryDistanceGuard) return true;
   if(!g_hasLastClosedDirection) return true; // no prior trade yet this session
   if(ReEntryDistanceSameDirectionOnly && wantBuy != g_lastClosedWasBuy) return true;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(wantBuy)
     {
      // Adverse side for a BUY re-entry is BELOW the last close
      if(proposedEntryPrice >= g_lastClosePrice) return true; // continuation side - always OK
      double dist = g_lastClosePrice - proposedEntryPrice;
      return (dist >= MinReEntryDistancePoints*point);
     }
   else
     {
      // Adverse side for a SELL re-entry is ABOVE the last close
      if(proposedEntryPrice <= g_lastClosePrice) return true; // continuation side - always OK
      double dist = proposedEntryPrice - g_lastClosePrice;
      return (dist >= MinReEntryDistancePoints*point);
     }
  }

//+------------------------------------------------------------------+
//| [Optional] RSI Divergence Guard.                                   |
//| Finds the two most recent swing highs (for a BUY) or swing lows    |
//| (for a SELL) and compares price vs RSI at those two points.        |
//|  - Bearish divergence: price makes a HIGHER high, RSI makes a      |
//|    LOWER high -> upside momentum isn't confirming the new price    |
//|    extreme -> block BUY.                                            |
//|  - Bullish divergence: price makes a LOWER low, RSI makes a        |
//|    HIGHER low -> downside momentum isn't confirming -> block SELL. |
//+------------------------------------------------------------------+
bool RSIDivergenceGuardOK(bool wantBuy)
  {
   if(!UseRSIDivergenceGuard) return true;

   int n = RSIDivergenceLookback;
   int s = RSIDivergenceSwingStrength;
   if(n - 2*s < 2) return true; // lookback too small for the given swing strength, don't block

   double rsiBuf[];
   ArraySetAsSeries(rsiBuf, true);
   if(CopyBuffer(rsiHandle, 0, 1, n, rsiBuf) < n) return true; // not enough data, don't block

   if(wantBuy)
     {
      double high[];
      ArraySetAsSeries(high, true);
      if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, n, high) < n) return true;

      int idxRecent = -1, idxOlder = -1, found = 0;
      for(int i = s; i < n - s; i++)
        {
         bool isHigh = true;
         for(int j = 1; j <= s; j++)
            if(high[i] < high[i-j] || high[i] < high[i+j]) { isHigh = false; break; }
         if(isHigh)
           {
            if(found == 0) { idxRecent = i; found = 1; }
            else { idxOlder = i; found = 2; break; }
           }
        }
      if(found < 2) return true; // not enough swing highs to compare, don't block

      double priceRecent = high[idxRecent], priceOlder = high[idxOlder];
      double rsiRecent = rsiBuf[idxRecent], rsiOlder = rsiBuf[idxOlder];

      if(priceRecent > priceOlder && rsiRecent < rsiOlder)
        {
         PrintFormat("[SMC EA] Bearish RSI divergence: price HH (%.2f > %.2f) but RSI LH (%.1f < %.1f) - blocking BUY",
                     priceRecent, priceOlder, rsiRecent, rsiOlder);
         return false;
        }
     }
   else
     {
      double low[];
      ArraySetAsSeries(low, true);
      if(CopyLow(_Symbol, PERIOD_CURRENT, 1, n, low) < n) return true;

      int idxRecent = -1, idxOlder = -1, found = 0;
      for(int i = s; i < n - s; i++)
        {
         bool isLow = true;
         for(int j = 1; j <= s; j++)
            if(low[i] > low[i-j] || low[i] > low[i+j]) { isLow = false; break; }
         if(isLow)
           {
            if(found == 0) { idxRecent = i; found = 1; }
            else { idxOlder = i; found = 2; break; }
           }
        }
      if(found < 2) return true;

      double priceRecent = low[idxRecent], priceOlder = low[idxOlder];
      double rsiRecent = rsiBuf[idxRecent], rsiOlder = rsiBuf[idxOlder];

      if(priceRecent < priceOlder && rsiRecent > rsiOlder)
        {
         PrintFormat("[SMC EA] Bullish RSI divergence: price LL (%.2f < %.2f) but RSI HL (%.1f > %.1f) - blocking SELL",
                     priceRecent, priceOlder, rsiRecent, rsiOlder);
         return false;
        }
     }
   return true;
  }

//+------------------------------------------------------------------+
//| [Optional] MACD Momentum Guard.                                    |
//|  - RequireMACDCrossConfirmation: MACD line must be on the correct  |
//|    side of the signal line for the trade direction.                |
//|  - BlockOnHistogramShrinking: even if the cross confirms, block if |
//|    the histogram magnitude has been shrinking for N straight bars  |
//|    (momentum decelerating even though nominally still in favor).   |
//+------------------------------------------------------------------+
bool MACDFilterOK(bool wantBuy)
  {
   if(!UseMACDFilter) return true;

   int need = MACD_HistogramShrinkBars + 2;
   double macdBuf[], signalBuf[];
   ArraySetAsSeries(macdBuf, true);
   ArraySetAsSeries(signalBuf, true);
   if(CopyBuffer(macdHandle, 0, 1, need, macdBuf) < need) return true;   // not enough data, don't block
   if(CopyBuffer(macdHandle, 1, 1, need, signalBuf) < need) return true;

   if(RequireMACDCrossConfirmation)
     {
      bool bullish = macdBuf[0] > signalBuf[0];
      if(wantBuy && !bullish)
        {
         PrintFormat("[SMC EA] MACD cross guard: MACD(%.4f) below Signal(%.4f) - blocking BUY", macdBuf[0], signalBuf[0]);
         return false;
        }
      if(!wantBuy && bullish)
        {
         PrintFormat("[SMC EA] MACD cross guard: MACD(%.4f) above Signal(%.4f) - blocking SELL", macdBuf[0], signalBuf[0]);
         return false;
        }
     }

   if(BlockOnHistogramShrinking)
     {
      bool shrinking = true;
      for(int i = 0; i < MACD_HistogramShrinkBars; i++)
        {
         double histNow  = MathAbs(macdBuf[i]   - signalBuf[i]);
         double histPrev = MathAbs(macdBuf[i+1] - signalBuf[i+1]);
         if(histNow >= histPrev) { shrinking = false; break; }
        }
      if(shrinking)
        {
         PrintFormat("[SMC EA] MACD histogram shrinking for %d bars - momentum fading, blocking %s",
                     MACD_HistogramShrinkBars, wantBuy ? "BUY" : "SELL");
         return false;
        }
     }
   return true;
  }

//+------------------------------------------------------------------+
//| [Optional] Multi-Timeframe Confirmation.                           |
//| Requires the higher timeframe's EMA alignment to agree with the    |
//| M5 signal direction before allowing entry - same EMA-crossover     |
//| logic as the existing M5 trend filter, just computed one level up. |
//+------------------------------------------------------------------+
bool MultiTimeframeFilterOK(bool wantBuy)
  {
   if(!UseMultiTimeframeFilter) return true;

   double fast[], slow[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   if(CopyBuffer(mtfEmaFastHandle, 0, 0, 1, fast) < 1) return true;  // not enough data yet, don't block
   if(CopyBuffer(mtfEmaSlowHandle, 0, 0, 1, slow) < 1) return true;

   bool higherTFBullish = fast[0] > slow[0];

   if(wantBuy && !higherTFBullish)
     {
      PrintFormat("[SMC EA] MTF filter: %s trend is bearish (EMA%d=%.2f < EMA%d=%.2f) - blocking BUY",
                  EnumToString(MTF_Timeframe), MTF_EMA_Fast, fast[0], MTF_EMA_Slow, slow[0]);
      return false;
     }
   if(!wantBuy && higherTFBullish)
     {
      PrintFormat("[SMC EA] MTF filter: %s trend is bullish (EMA%d=%.2f > EMA%d=%.2f) - blocking SELL",
                  EnumToString(MTF_Timeframe), MTF_EMA_Fast, fast[0], MTF_EMA_Slow, slow[0]);
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| [Optional] Breakout Extension Filter.                              |
//| "Support broken at 4040, but by the time the SELL confirms,       |
//| price is already at 4025 - 15 points of the move already spent."   |
//| Rejects entries where the actual entry price has already drifted   |
//| too far from the level whose breakout triggered the setup -        |
//| overextended entries have less room/momentum left and are more     |
//| prone to snapping back.                                            |
//+------------------------------------------------------------------+
bool BreakoutExtensionFilterOK(double entryPrice)
  {
   if(!UseBreakoutExtensionFilter) return true;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double extension = MathAbs(entryPrice - pendingLevel);

   if(extension > MaxExtensionPoints*point)
     {
      PrintFormat("[SMC EA] Breakout extension filter: entry %.2f is %.0f points from broken level %.2f (max %.0f) - too extended",
                  entryPrice, extension/point, pendingLevel, MaxExtensionPoints);
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| [Optional] Retest Entry.                                           |
//| When the extension filter rejects a trade for being too far from   |
//| the broken level, this remembers the REJECTED entry price itself   |
//| (not the far-away original level) and waits for price to pull      |
//| back to/past that specific, realistic price before firing - a      |
//| classic breakout-then-retest entry instead of chasing an already   |
//| extended move or abandoning the setup entirely.                    |
//+------------------------------------------------------------------+
void ManageRetestEntry()
  {
   if(!UseRetestEntry) return;
   if(!g_retestPending) return;

   if(barCounter - g_retestStartBar > RetestMaxWaitBars)
     {
      PrintFormat("[SMC EA] Retest entry EXPIRED after %d bars without pullback", RetestMaxWaitBars);
      g_retestPending = false;
      return;
     }

   double currentPrice = g_retestIsBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool pulledBack = g_retestIsBuy ? (currentPrice <= g_retestRefPrice) : (currentPrice >= g_retestRefPrice);
   if(!pulledBack) return; // still extended, keep waiting

   g_retestPending = false; // consume regardless of outcome below
   PrintFormat("[SMC EA] Retest entry triggered: price returned to %.2f (target was %.2f)", currentPrice, g_retestRefPrice);

   // Temporarily restore the stored setup's context so TryOpenBuy/TryOpenSell build
   // the right SL/TP/logging - safe since pendingType is PENDING_NONE at this point
   // (this setup already fully resolved through the main state machine earlier).
   pendingLevel     = g_retestLevel;
   pendingTag       = g_retestTag;
   pendingHasFVG_OB = g_retestZoneNote;

   g_retestFiring = true; // prevents this attempt from re-arming a fresh wait window if it fails again
   if(g_retestIsBuy) TryOpenBuy(g_retestZone);
   else               TryOpenSell(g_retestZone);
   g_retestFiring = false;
  }

//+------------------------------------------------------------------+
//| Main signal + execution logic (runs once per new bar)            |
//+------------------------------------------------------------------+
void CheckForSignal()
  {
   if(IsWeekendCloseWindow())  return; // Friday-close filter: don't even scan for new setups
   if(DailyDrawdownLockActive()) return; // Circuit breaker tripped today: no new setups until midnight
   if(IsNewsBlackoutWindow())  return; // News filter: don't scan for new setups near a matching event

   int barsNeeded = MathMax(SwingLookback, MathMax(FVG_LookbackBars, OB_LookbackBars)) + 60;

   double open[], high[], low[], close[];
   ArraySetAsSeries(open,false);
   ArraySetAsSeries(high,false);
   ArraySetAsSeries(low,false);
   ArraySetAsSeries(close,false);

   int copied = CopyOpen(_Symbol, PERIOD_CURRENT, 0, barsNeeded, open);
   CopyHigh(_Symbol, PERIOD_CURRENT, 0, barsNeeded, high);
   CopyLow(_Symbol, PERIOD_CURRENT, 0, barsNeeded, low);
   CopyClose(_Symbol, PERIOD_CURRENT, 0, barsNeeded, close);

   if(copied < barsNeeded/2) return; // not enough history yet

   int bars = ArraySize(close);
   int lastClosed = bars - 1; // index of most recently CLOSED bar (bar 0 on chart is still forming and excluded by CopyX with shift 0..N-1 including current; we treat last as latest closed since new bar just opened)

   double lastClose = close[lastClosed];

   // ================================================================
   // PHASE 1: We already have a pending breakout awaiting confirmation.
   // Check whether the latest closed candle kept it alive.
   // ================================================================
   if(pendingType == PENDING_BUY)
     {
      // Confirmation candle must OPEN above AND CLOSE above the breakout level
      bool candleConfirms = (open[lastClosed] > pendingLevel) && (lastClose > pendingLevel);
      if(candleConfirms)
        {
         pendingConfirmed++;
         PrintFormat("[SMC EA] BUY confirmation %d/%d: Open=%.2f Close=%.2f both above level %.2f",
                     pendingConfirmed, ConfirmationCandles, open[lastClosed], lastClose, pendingLevel);
         if(pendingConfirmed >= ConfirmationCandles)
           {
            TryOpenBuy(pendingZone);   // fully confirmed -> attempt entry
            pendingType = PENDING_NONE;
           }
         else if(barCounter - pendingStartBar > MaxWaitBarsForConfirmation)
           {
            PrintFormat("[SMC EA] BUY setup expired waiting for confirmation (level %.2f)", pendingLevel);
            pendingType = PENDING_NONE; // took too long, drop it
           }
        }
      else
        {
         // opened or closed back inside the level -> false breakout, cancel
         PrintFormat("[SMC EA] BUY setup CANCELLED - pullback: Open=%.2f Close=%.2f vs level %.2f",
                     open[lastClosed], lastClose, pendingLevel);
         pendingType = PENDING_NONE;
        }
      if(ShowDashboard) UpdateDashboard(lastClose);
      return; // don't also scan for a brand-new breakout on this same bar
     }
   else if(pendingType == PENDING_SELL)
     {
      // Confirmation candle must OPEN below AND CLOSE below the breakout level
      bool candleConfirms = (open[lastClosed] < pendingLevel) && (lastClose < pendingLevel);
      if(candleConfirms)
        {
         pendingConfirmed++;
         PrintFormat("[SMC EA] SELL confirmation %d/%d: Open=%.2f Close=%.2f both below level %.2f",
                     pendingConfirmed, ConfirmationCandles, open[lastClosed], lastClose, pendingLevel);
         if(pendingConfirmed >= ConfirmationCandles)
           {
            TryOpenSell(pendingZone);
            pendingType = PENDING_NONE;
           }
         else if(barCounter - pendingStartBar > MaxWaitBarsForConfirmation)
           {
            PrintFormat("[SMC EA] SELL setup expired waiting for confirmation (level %.2f)", pendingLevel);
            pendingType = PENDING_NONE;
           }
        }
      else
        {
         PrintFormat("[SMC EA] SELL setup CANCELLED - pullback: Open=%.2f Close=%.2f vs level %.2f",
                     open[lastClosed], lastClose, pendingLevel);
         pendingType = PENDING_NONE; // opened or closed back above level -> cancel
        }
      if(ShowDashboard) UpdateDashboard(lastClose);
      return;
     }

   // ================================================================
   // PHASE 2: No pending breakout -- look for a fresh one. If found,
   // we do NOT trade yet: we arm the state machine and wait for
   // ConfirmationCandles closes beyond the level before entering.
   // ================================================================
   double resistance=0, support=0;
   int rIdx=0, sIdx=0;
   bool haveRes = FindSwingHigh(high, bars, resistance, rIdx);
   bool haveSup = FindSwingLow(low, bars, support, sIdx);
   if(!haveRes || !haveSup) return;

   if(lastClose > resistance)
     {
      double fvgLow, fvgHigh, obLow, obHigh;
      bool hasFVG = FindBullishFVG(high, low, close, bars, fvgLow, fvgHigh);
      bool hasOB  = FindBullishOB(open, high, low, close, bars, obLow, obHigh);
      bool structureOK = RequireBothFVGAndOB ? (hasFVG && hasOB) : (hasFVG || hasOB);

      if(structureOK)
        {
         double zoneLow = 0;
         string zoneNote = "";
         string tag = "";
         if(hasFVG && hasOB) { zoneLow = MathMin(fvgLow, obLow); zoneNote = StringFormat("FVG[%.2f-%.2f] + OB[%.2f-%.2f]", fvgLow, fvgHigh, obLow, obHigh); tag = "FVG+OB"; }
         else if(hasFVG)     { zoneLow = fvgLow;                 zoneNote = StringFormat("FVG only [%.2f-%.2f]", fvgLow, fvgHigh); tag = "FVG"; }
         else                 { zoneLow = obLow;                 zoneNote = StringFormat("OB only [%.2f-%.2f]", obLow, obHigh); tag = "OB"; }

         pendingType      = PENDING_BUY;
         pendingLevel     = resistance;
         pendingZone      = zoneLow;
         pendingConfirmed = 1;              // this candle is confirmation #1
         pendingStartBar  = barCounter;
         pendingHasFVG_OB = zoneNote;
         pendingTag       = tag;

         PrintFormat("[SMC EA] BUY breakout armed: Resistance=%.2f broken, Close=%.2f, Zone=%s. Waiting for %d confirming candle(s).",
                     resistance, lastClose, zoneNote, ConfirmationCandles);

         if(pendingConfirmed >= ConfirmationCandles)
           {
            TryOpenBuy(pendingZone);
            pendingType = PENDING_NONE;
           }
        }
     }
   else if(lastClose < support)
     {
      double fvgLow, fvgHigh, obLow, obHigh;
      bool hasFVG = FindBearishFVG(high, low, close, bars, fvgLow, fvgHigh);
      bool hasOB  = FindBearishOB(open, high, low, close, bars, obLow, obHigh);
      bool structureOK = RequireBothFVGAndOB ? (hasFVG && hasOB) : (hasFVG || hasOB);

      if(structureOK)
        {
         double zoneHigh = 0;
         string zoneNote = "";
         string tag = "";
         if(hasFVG && hasOB) { zoneHigh = MathMax(fvgHigh, obHigh); zoneNote = StringFormat("FVG[%.2f-%.2f] + OB[%.2f-%.2f]", fvgLow, fvgHigh, obLow, obHigh); tag = "FVG+OB"; }
         else if(hasFVG)     { zoneHigh = fvgHigh;                  zoneNote = StringFormat("FVG only [%.2f-%.2f]", fvgLow, fvgHigh); tag = "FVG"; }
         else                 { zoneHigh = obHigh;                  zoneNote = StringFormat("OB only [%.2f-%.2f]", obLow, obHigh); tag = "OB"; }

         pendingType      = PENDING_SELL;
         pendingLevel     = support;
         pendingZone      = zoneHigh;
         pendingConfirmed = 1;
         pendingStartBar  = barCounter;
         pendingHasFVG_OB = zoneNote;
         pendingTag       = tag;

         PrintFormat("[SMC EA] SELL breakout armed: Support=%.2f broken, Close=%.2f, Zone=%s. Waiting for %d confirming candle(s).",
                     support, lastClose, zoneNote, ConfirmationCandles);

         if(pendingConfirmed >= ConfirmationCandles)
           {
            TryOpenSell(pendingZone);
            pendingType = PENDING_NONE;
           }
        }
     }

   if(ShowDashboard) UpdateDashboard(lastClose);
  }

//+------------------------------------------------------------------+
void UpdateDashboard(double lastClose)
  {
   string state = "None";
   if(pendingType == PENDING_BUY)  state = StringFormat("BUY watch (%d/%d closes above %.2f)", pendingConfirmed, ConfirmationCandles, pendingLevel);
   if(pendingType == PENDING_SELL) state = StringFormat("SELL watch (%d/%d closes below %.2f)", pendingConfirmed, ConfirmationCandles, pendingLevel);

   string txt = StringFormat(
      "SMC FVG/OB EA - %s\nLast Close: %.2f\nPending Breakout: %s\nOpen Positions: %d\nTrades Today: %d / %d\n\nLast Trade: %s",
      _Symbol, lastClose, state, CountOpenPositions(), tradesToday, MaxTradesPerDay, g_lastTradeReason);
   Comment(txt);
  }

//+------------------------------------------------------------------+
void TryOpenBuy(double zoneLow)
  {
   // Record this confirmed signal regardless of what happens next - used by the
   // Opposite Signal Exit's "require confirmation" mode, which needs to see confirmed
   // signals even when they get rejected below (e.g. by "position already open").
   g_lastConfirmedSignalBar   = barCounter;
   g_lastConfirmedSignalIsBuy = true;

   if(IsWeekendCloseWindow()) { PrintFormat("[SMC EA] BUY signal REJECTED: weekend close window"); return; }
   if(DailyDrawdownLockActive()) { PrintFormat("[SMC EA] BUY signal REJECTED: daily drawdown lock active"); return; }
   if(IsNewsBlackoutWindow()) { PrintFormat("[SMC EA] BUY signal REJECTED: news blackout (%s)", g_newsCacheEventName); return; }
   if(OnePositionAtATime && CountOpenPositions() > 0) { PrintFormat("[SMC EA] BUY signal REJECTED: position already open"); return; }
   if(!BreakoutExtensionFilterOK(SymbolInfoDouble(_Symbol, SYMBOL_ASK)))
     {
      PrintFormat("[SMC EA] BUY signal REJECTED: breakout extension filter");
      if(UseRetestEntry && !g_retestFiring)
        {
         g_retestPending  = true;
         g_retestIsBuy    = true;
         g_retestLevel    = pendingLevel;
         g_retestZone     = zoneLow;
         g_retestRefPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK); // the rejected entry price itself
         g_retestTag      = pendingTag;
         g_retestZoneNote = pendingHasFVG_OB;
         g_retestStartBar = barCounter;
         PrintFormat("[SMC EA] Retest entry armed: waiting for price to pull back to <= %.2f (max %d bars)", g_retestRefPrice, RetestMaxWaitBars);
        }
      return;
     }
   if(!ReversalGuardOK(true)) { PrintFormat("[SMC EA] BUY signal REJECTED: reversal candle guard"); return; }
   if(!ReEntryDistanceOK(true, SymbolInfoDouble(_Symbol, SYMBOL_ASK)))
     {
      PrintFormat("[SMC EA] BUY signal REJECTED: re-entry distance guard (last close=%.2f, now=%.2f, dist=%.0fpts, need>=%.0fpts)",
                  g_lastClosePrice, SymbolInfoDouble(_Symbol, SYMBOL_ASK),
                  MathAbs(SymbolInfoDouble(_Symbol, SYMBOL_ASK)-g_lastClosePrice)/SymbolInfoDouble(_Symbol,SYMBOL_POINT), MinReEntryDistancePoints);
      return;
     }
   if(!RSIDivergenceGuardOK(true)) { PrintFormat("[SMC EA] BUY signal REJECTED: RSI divergence guard"); return; }
   if(!MACDFilterOK(true))         { PrintFormat("[SMC EA] BUY signal REJECTED: MACD momentum guard"); return; }
   if(!TradingHoursFilterOK())     { PrintFormat("[SMC EA] BUY signal REJECTED: trading hours filter"); return; }
   if(!DirectionChangeCooldownOK(true))
     {
      double remain = DirectionChangeCooldownMinutes*60 - (double)((long)TimeCurrent()-(long)g_lastCloseTime);
      PrintFormat("[SMC EA] BUY signal REJECTED: direction-change cooldown active (%.0f sec remaining)", MathMax(remain,0));
      return;
     }
   if(!SpreadOK()) { PrintFormat("[SMC EA] BUY signal REJECTED: spread too wide (%d pts)", (int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)); return; }
   string limitReason = TradeLimitsRejectReason();
   if(limitReason != "") { PrintFormat("[SMC EA] BUY signal REJECTED: %s", limitReason); return; }
   if(!TrendFilterOK(true))  { PrintFormat("[SMC EA] BUY signal REJECTED: trend filter (EMA fast not above EMA slow)"); return; }
   if(!MultiTimeframeFilterOK(true)) return; // MultiTimeframeFilterOK already logs its own rejection reason
   if(!RSIFilterOK(true))    { PrintFormat("[SMC EA] BUY signal REJECTED: RSI filter (RSI=%.1f)", GetRSISnapshot()); return; }
   if(!VolumeFilterOK())     { double cv,av; GetVolumeSnapshot(cv,av); PrintFormat("[SMC EA] BUY signal REJECTED: volume filter (vol=%.0f avg=%.0f need>%.0f, %.2fx avg vs required %.2fx)", cv, av, av*VolumeMultiplier, (av>0?cv/av:0), VolumeMultiplier); return; }
   if(!ADXFilterOK())        { PrintFormat("[SMC EA] BUY signal REJECTED: ADX filter (market too choppy)"); return; }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double sl, tp, slDist;

   if(UseStaticSLTP)
     {
      slDist = StaticSL_Points * point;
      sl     = ask - slDist;
      tp     = ask + StaticTP_Points * point;
     }
   else
     {
      double atr = GetATR();
      double buffer = atr * ATR_BufferMultiplier;

      sl = zoneLow - buffer;
      slDist = ask - sl;
      if(slDist <= 0) return;

      double minDist = MinStopPoints * point;
      if(slDist < minDist)
        {
         slDist = minDist;
         sl = ask - slDist;
        }

      tp = ask + slDist * RiskRewardRatio;
     }

   double lots = CalculateLotSize(slDist);

   if(lots <= 0) { PrintFormat("[SMC EA] Signal REJECTED: calculated lot size was zero/invalid (SL dist=%.2f)", slDist); return; }

   double rsiVal[]; ArraySetAsSeries(rsiVal,true); CopyBuffer(rsiHandle,0,1,1,rsiVal);
   double adxVal[]; ArraySetAsSeries(adxVal,true); CopyBuffer(adxHandle,0,1,1,adxVal);

   string reason = StringFormat(
      "BUY | Level(Resistance)=%.2f broken | Zone=%s | Entry=%.2f SL=%.2f (%.0f pts) TP=%.2f (%.0f pts) | RSI=%.1f ADX=%.1f",
      pendingLevel, pendingHasFVG_OB, ask, sl, slDist/point, tp, MathAbs(tp-ask)/point,
      ArraySize(rsiVal)>0?rsiVal[0]:0, ArraySize(adxVal)>0?adxVal[0]:0);

   string shortComment = StringFormat("BO-Resistance %.2f %s", pendingLevel, pendingTag);
   if(trade.Buy(lots, _Symbol, ask, NormalizeDouble(sl,_Digits), NormalizeDouble(tp,_Digits), shortComment))
     {
      RegisterTradeTaken();
      g_lastTradeReason = reason;
      g_openPosTriggerLevel = pendingLevel; // [Optional] for the Early Invalidation Exit
      g_openPosIsBuy         = true;
      g_openPosActive        = true;
      PrintFormat("[SMC EA] TRADE OPENED - %s", reason);
      if(TelegramNotifyOnOpen)
         SendTelegramMessage(StringFormat("🟢 BUY %s\nLot: %.2f\nEntry: %.2f\nSL: %.2f (%.0f pts)\nTP: %.2f (%.0f pts)\nLevel: %.2f | %s",
                              _Symbol, lots, ask, sl, slDist/point, tp, MathAbs(tp-ask)/point, pendingLevel, pendingTag));
     }
   else
     {
      PrintFormat("[SMC EA] BUY ORDER SEND FAILED: retcode=%d (%s)", trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
  }

void TryOpenSell(double zoneHigh)
  {
   g_lastConfirmedSignalBar   = barCounter;
   g_lastConfirmedSignalIsBuy = false;

   if(IsWeekendCloseWindow()) { PrintFormat("[SMC EA] SELL signal REJECTED: weekend close window"); return; }
   if(DailyDrawdownLockActive()) { PrintFormat("[SMC EA] SELL signal REJECTED: daily drawdown lock active"); return; }
   if(IsNewsBlackoutWindow()) { PrintFormat("[SMC EA] SELL signal REJECTED: news blackout (%s)", g_newsCacheEventName); return; }
   if(OnePositionAtATime && CountOpenPositions() > 0) { PrintFormat("[SMC EA] SELL signal REJECTED: position already open"); return; }
   if(!BreakoutExtensionFilterOK(SymbolInfoDouble(_Symbol, SYMBOL_BID)))
     {
      PrintFormat("[SMC EA] SELL signal REJECTED: breakout extension filter");
      if(UseRetestEntry && !g_retestFiring)
        {
         g_retestPending  = true;
         g_retestIsBuy    = false;
         g_retestLevel    = pendingLevel;
         g_retestZone     = zoneHigh;
         g_retestRefPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         g_retestTag      = pendingTag;
         g_retestZoneNote = pendingHasFVG_OB;
         g_retestStartBar = barCounter;
         PrintFormat("[SMC EA] Retest entry armed: waiting for price to return to >= %.2f (max %d bars)", g_retestRefPrice, RetestMaxWaitBars);
        }
      return;
     }
   if(!ReversalGuardOK(false)) { PrintFormat("[SMC EA] SELL signal REJECTED: reversal candle guard"); return; }
   if(!ReEntryDistanceOK(false, SymbolInfoDouble(_Symbol, SYMBOL_BID)))
     {
      PrintFormat("[SMC EA] SELL signal REJECTED: re-entry distance guard (last close=%.2f, now=%.2f, dist=%.0fpts, need>=%.0fpts)",
                  g_lastClosePrice, SymbolInfoDouble(_Symbol, SYMBOL_BID),
                  MathAbs(SymbolInfoDouble(_Symbol, SYMBOL_BID)-g_lastClosePrice)/SymbolInfoDouble(_Symbol,SYMBOL_POINT), MinReEntryDistancePoints);
      return;
     }
   if(!RSIDivergenceGuardOK(false)) { PrintFormat("[SMC EA] SELL signal REJECTED: RSI divergence guard"); return; }
   if(!MACDFilterOK(false))         { PrintFormat("[SMC EA] SELL signal REJECTED: MACD momentum guard"); return; }
   if(!TradingHoursFilterOK())      { PrintFormat("[SMC EA] SELL signal REJECTED: trading hours filter"); return; }
   if(!DirectionChangeCooldownOK(false))
     {
      double remain = DirectionChangeCooldownMinutes*60 - (double)((long)TimeCurrent()-(long)g_lastCloseTime);
      PrintFormat("[SMC EA] SELL signal REJECTED: direction-change cooldown active (%.0f sec remaining)", MathMax(remain,0));
      return;
     }
   if(!SpreadOK()) { PrintFormat("[SMC EA] SELL signal REJECTED: spread too wide (%d pts)", (int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)); return; }
   string limitReason = TradeLimitsRejectReason();
   if(limitReason != "") { PrintFormat("[SMC EA] SELL signal REJECTED: %s", limitReason); return; }
   if(!TrendFilterOK(false)) { PrintFormat("[SMC EA] SELL signal REJECTED: trend filter (EMA fast not below EMA slow)"); return; }
   if(!MultiTimeframeFilterOK(false)) return; // MultiTimeframeFilterOK already logs its own rejection reason
   if(!RSIFilterOK(false))   { PrintFormat("[SMC EA] SELL signal REJECTED: RSI filter (RSI=%.1f)", GetRSISnapshot()); return; }
   if(!VolumeFilterOK())     { double cv,av; GetVolumeSnapshot(cv,av); PrintFormat("[SMC EA] SELL signal REJECTED: volume filter (vol=%.0f avg=%.0f need>%.0f, %.2fx avg vs required %.2fx)", cv, av, av*VolumeMultiplier, (av>0?cv/av:0), VolumeMultiplier); return; }
   if(!ADXFilterOK())        { PrintFormat("[SMC EA] SELL signal REJECTED: ADX filter (market too choppy)"); return; }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double sl, tp, slDist;

   if(UseStaticSLTP)
     {
      slDist = StaticSL_Points * point;
      sl     = bid + slDist;
      tp     = bid - StaticTP_Points * point;
     }
   else
     {
      double atr = GetATR();
      double buffer = atr * ATR_BufferMultiplier;

      sl = zoneHigh + buffer;
      slDist = sl - bid;
      if(slDist <= 0) return;

      double minDist = MinStopPoints * point;
      if(slDist < minDist)
        {
         slDist = minDist;
         sl = bid + slDist;
        }

      tp = bid - slDist * RiskRewardRatio;
     }

   double lots = CalculateLotSize(slDist);

   if(lots <= 0) { PrintFormat("[SMC EA] Signal REJECTED: calculated lot size was zero/invalid (SL dist=%.2f)", slDist); return; }

   double rsiVal[]; ArraySetAsSeries(rsiVal,true); CopyBuffer(rsiHandle,0,1,1,rsiVal);
   double adxVal[]; ArraySetAsSeries(adxVal,true); CopyBuffer(adxHandle,0,1,1,adxVal);

   string reason = StringFormat(
      "SELL | Level(Support)=%.2f broken | Zone=%s | Entry=%.2f SL=%.2f (%.0f pts) TP=%.2f (%.0f pts) | RSI=%.1f ADX=%.1f",
      pendingLevel, pendingHasFVG_OB, bid, sl, slDist/point, tp, MathAbs(bid-tp)/point,
      ArraySize(rsiVal)>0?rsiVal[0]:0, ArraySize(adxVal)>0?adxVal[0]:0);

   string shortComment = StringFormat("BO-Support %.2f %s", pendingLevel, pendingTag);
   if(trade.Sell(lots, _Symbol, bid, NormalizeDouble(sl,_Digits), NormalizeDouble(tp,_Digits), shortComment))
     {
      RegisterTradeTaken();
      g_lastTradeReason = reason;
      g_openPosTriggerLevel = pendingLevel; // [Optional] for the Early Invalidation Exit
      g_openPosIsBuy         = false;
      g_openPosActive        = true;
      PrintFormat("[SMC EA] TRADE OPENED - %s", reason);
      if(TelegramNotifyOnOpen)
         SendTelegramMessage(StringFormat("🔴 SELL %s\nLot: %.2f\nEntry: %.2f\nSL: %.2f (%.0f pts)\nTP: %.2f (%.0f pts)\nLevel: %.2f | %s",
                              _Symbol, lots, bid, sl, slDist/point, tp, MathAbs(bid-tp)/point, pendingLevel, pendingTag));
     }
   else
     {
      PrintFormat("[SMC EA] SELL ORDER SEND FAILED: retcode=%d (%s)", trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Safety/risk-management checks run every tick, ahead of everything else
   ManageFridayForceClose();
   ManageDailyDrawdownCircuitBreaker();
   ManageNewsFilter();

   ManageMarketStructureTrail();
   ManageStagedBreakevenTrail();
   ManageTrailing();
   ManageBreakevenLock();
   ManageReverseTrade();

   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == lastBarTime) return; // only act once per new bar
   lastBarTime = currentBarTime;
   barCounter++;

   ManageInvalidationExit();
   ManageOppositeSignalExit();
   ManageRetestEntry();
   ManageStructureBreakExit();
   ManageMomentumExit();
   ManageEMAInvalidationExit();
   CheckForSignal();
  }
//+------------------------------------------------------------------+

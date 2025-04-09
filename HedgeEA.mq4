//+------------------------------------------------------------------+
//|                                                      HedgeEA.mq4 |
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

// Input Parameters
input double   LotSize = 0.1;           // Lot Size
input double   HedgeLotSize = 0.1;      // Hedge Lot Size
input int      StopLoss = 50;           // Stop Loss in pips
input int      TakeProfit = 100;        // Take Profit in pips
input int      MagicNumber = 123456;    // Magic Number
input int      Slippage = 3;            // Slippage in pips
input double   MaxLossPercent = 1.0;    // Maximum Loss Percent before Hedging
input double   TargetProfit = 2.0;      // Target Profit Percent to Close All
input int      StartHour = 0;           // Trading Start Hour
input int      EndHour = 24;            // Trading End Hour
input double   MaxMarginLevel = 1000;   // Maximum margin level before closing positions
input bool     UseTrailingStop = true;  // Use trailing stop
input int      TrailingStop = 20;       // Trailing stop in pips
input int      TrailingStep = 5;        // Trailing step in pips
input bool     UseDynamicLotSize = false; // Use dynamic lot size
input double   RiskPercent = 1.0;       // Risk percent for dynamic lot size
input int      MaxPositionAge = 24;     // Maximum position age in hours
input bool     UseNewsFilter = true;    // Use news filter
input int      NewsMinutesBefore = 30;  // Minutes before news to avoid trading
input int      NewsMinutesAfter = 30;   // Minutes after news to avoid trading
input bool     UseSessionFilter = true; // Use session filter
input string   AsianSession = "00:00-08:00";    // Asian session
input string   LondonSession = "08:00-16:00";   // London session
input string   NewYorkSession = "13:00-21:00";  // New York session
input bool     UseRiskManagement = true;        // Use advanced risk management
input double   DailyLossLimit = 2.0;    // Daily loss limit in percent
input double   WeeklyLossLimit = 5.0;   // Weekly loss limit in percent

// Global Variables
int ticket = 0;
bool hedgedPositions[];  // Array to track hedged positions
int totalPositions = 0;
datetime lastTradeTime = 0;
double dailyProfit = 0;
double weeklyProfit = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ArrayResize(hedgedPositions, 100);  // Initialize array for 100 positions
   ArrayInitialize(hedgedPositions, false);
   lastTradeTime = TimeCurrent();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ArrayFree(hedgedPositions);
}

//+------------------------------------------------------------------+
//| Check if trading is allowed in current time                      |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   int currentHour = TimeHour(TimeCurrent());
   return (currentHour >= StartHour && currentHour < EndHour);
}

//+------------------------------------------------------------------+
//| Check if current time is within a trading session                |
//+------------------------------------------------------------------+
bool IsInSession(string session)
{
   string times[];
   StringSplit(session, '-', times);
   if(ArraySize(times) != 2) return false;
   
   string currentTime = TimeToString(TimeCurrent(), TIME_MINUTES);
   return (currentTime >= times[0] && currentTime < times[1]);
}

//+------------------------------------------------------------------+
//| Check if trading is allowed based on sessions                    |
//+------------------------------------------------------------------+
bool IsSessionAllowed()
{
   if(!UseSessionFilter) return true;
   
   return (IsInSession(AsianSession) || IsInSession(LondonSession) || IsInSession(NewYorkSession));
}

//+------------------------------------------------------------------+
//| Check if there is important news coming                          |
//+------------------------------------------------------------------+
bool IsNewsTime()
{
   if(!UseNewsFilter) return false;
   
   // Here you would implement your news checking logic
   // This is a placeholder - you would need to integrate with a news API
   return false;
}

//+------------------------------------------------------------------+
//| Calculate total profit of all positions                          |
//+------------------------------------------------------------------+
double CalculateTotalProfit()
{
   double totalProfit = 0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderMagicNumber() == MagicNumber)
         {
            totalProfit += OrderProfit();
         }
      }
   }
   return totalProfit;
}

//+------------------------------------------------------------------+
//| Calculate dynamic lot size based on risk                         |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   if(!UseDynamicLotSize) return LotSize;
   
   double riskAmount = AccountBalance() * RiskPercent / 100;
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double stopLossPoints = StopLoss * Point;
   
   return NormalizeDouble(riskAmount / (stopLossPoints * tickValue), 2);
}

//+------------------------------------------------------------------+
//| Check if position is too old                                     |
//+------------------------------------------------------------------+
bool IsPositionTooOld(int ticket)
{
   if(OrderSelect(ticket, SELECT_BY_TICKET))
   {
      datetime positionAge = TimeCurrent() - OrderOpenTime();
      return (positionAge > MaxPositionAge * 3600);
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if daily or weekly loss limits are reached                 |
//+------------------------------------------------------------------+
bool IsLossLimitReached()
{
   if(!UseRiskManagement) return false;
   
   datetime currentTime = TimeCurrent();
   if(TimeDay(currentTime) != TimeDay(lastTradeTime))
   {
      dailyProfit = 0;
      lastTradeTime = currentTime;
   }
   
   if(TimeDayOfWeek(currentTime) == 0) // Sunday
   {
      weeklyProfit = 0;
   }
   
   double currentProfit = CalculateTotalProfit();
   dailyProfit += currentProfit;
   weeklyProfit += currentProfit;
   
   return (dailyProfit <= -AccountBalance() * DailyLossLimit / 100 ||
           weeklyProfit <= -AccountBalance() * WeeklyLossLimit / 100);
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderMagicNumber() == MagicNumber)
         {
            bool result = false;
            if(OrderType() == OP_BUY)
               result = OrderClose(OrderTicket(), OrderLots(), Bid, Slippage, clrRed);
            else if(OrderType() == OP_SELL)
               result = OrderClose(OrderTicket(), OrderLots(), Ask, Slippage, clrGreen);
            
            if(!result)
            {
               Print("Error closing order #", OrderTicket(), ": ", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if trading conditions are met                              |
//+------------------------------------------------------------------+
bool CheckTradeConditions()
{
   if(!IsTradeAllowed()) return false;
   if(!IsTradingTime()) return false;
   if(!IsSessionAllowed()) return false;
   if(IsNewsTime()) return false;
   if(AccountMargin() > MaxMarginLevel) return false;
   if(IsLossLimitReached()) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Print trade information                                          |
//+------------------------------------------------------------------+
void PrintTradeInfo()
{
   Print("Total Positions: ", OrdersTotal());
   Print("Total Profit: ", CalculateTotalProfit());
   Print("Account Balance: ", AccountBalance());
   Print("Daily Profit: ", dailyProfit);
   Print("Weekly Profit: ", weeklyProfit);
   Print("Current Session: ", IsInSession(AsianSession) ? "Asian" : 
                            (IsInSession(LondonSession) ? "London" : 
                            (IsInSession(NewYorkSession) ? "New York" : "No Session")));
}

//+------------------------------------------------------------------+
//| Check if lot size is valid and can be opened                     |
//+------------------------------------------------------------------+
bool IsValidLotSize(double lot)
{
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   
   // بررسی محدوده حجم
   if(lot < minLot || lot > maxLot)
   {
      Print("Invalid lot size: ", lot, " (Min: ", minLot, ", Max: ", maxLot, ")");
      return false;
   }
   
   // بررسی گام حجم
   if(MathAbs(MathMod(lot, lotStep)) > 0.00001)
   {
      Print("Lot size must be a multiple of ", lotStep);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if there is enough margin to open position                  |
//+------------------------------------------------------------------+
bool HasEnoughMargin(int type, double lot)
{
   double margin = MarketInfo(Symbol(), MODE_MARGINREQUIRED) * lot;
   double freeMargin = AccountFreeMargin();
   
   if(freeMargin < margin)
   {
      Print("Not enough margin. Required: ", margin, ", Free: ", freeMargin);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Try to reduce lot size if original size cannot be opened          |
//+------------------------------------------------------------------+
double GetAdjustedLotSize(double originalLot)
{
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   double adjustedLot = originalLot;
   
   while(adjustedLot > minLot)
   {
      if(IsValidLotSize(adjustedLot) && HasEnoughMargin(OP_BUY, adjustedLot))
      {
         Print("Adjusted lot size from ", originalLot, " to ", adjustedLot);
         return adjustedLot;
      }
      adjustedLot -= lotStep;
   }
   
   return 0; // اگر هیچ حجمی نتواند باز شود
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!CheckTradeConditions()) return;

   // Check total profit and close all if target reached
   double totalProfit = CalculateTotalProfit();
   if(totalProfit >= AccountBalance() * TargetProfit / 100)
   {
      CloseAllPositions();
      return;
   }

   // Check if we have any open positions
   if(OrdersTotal() > 0)
   {
      for(int i = 0; i < OrdersTotal(); i++)
      {
         if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         {
            if(OrderMagicNumber() == MagicNumber)
            {
               // Check if position is too old
               if(IsPositionTooOld(OrderTicket()))
               {
                  bool result = false;
                  if(OrderType() == OP_BUY)
                     result = OrderClose(OrderTicket(), OrderLots(), Bid, Slippage, clrRed);
                  else if(OrderType() == OP_SELL)
                     result = OrderClose(OrderTicket(), OrderLots(), Ask, Slippage, clrGreen);
                  continue;
               }

               // Calculate loss percentage
               double lossPercent = MathAbs(OrderProfit()) / AccountBalance() * 100;
               
               // If position is in loss and not hedged yet and loss exceeds threshold
               if(OrderProfit() < 0 && !hedgedPositions[OrderTicket()] && lossPercent >= MaxLossPercent)
               {
                  double hedgeLot = CalculateLotSize();
                  
                  // بررسی و تنظیم حجم
                  if(!IsValidLotSize(hedgeLot) || !HasEnoughMargin(OrderType() == OP_BUY ? OP_SELL : OP_BUY, hedgeLot))
                  {
                     hedgeLot = GetAdjustedLotSize(hedgeLot);
                     if(hedgeLot == 0)
                     {
                        Print("Cannot open hedge position - no valid lot size available");
                        // اینجا می‌توانید تصمیم بگیرید چه کاری انجام شود
                        // مثلاً بستن پوزیشن اصلی یا ارسال هشدار
                        if(CloseOnHedgeFailure) // یک پارامتر جدید
                        {
                           OrderClose(OrderTicket(), OrderLots(), 
                                     OrderType() == OP_BUY ? Bid : Ask, 
                                     Slippage, clrRed);
                           Print("Closed original position due to hedge failure");
                        }
                        continue;
                     }
                  }
                  
                  // باز کردن پوزیشن هدج با حجم تنظیم شده
                  if(OrderType() == OP_BUY)
                  {
                     ticket = OrderSend(Symbol(), OP_SELL, hedgeLot, Bid, Slippage, 
                                       OrderOpenPrice() + StopLoss * Point, 
                                       OrderOpenPrice() - TakeProfit * Point, 
                                       "Hedge", MagicNumber, 0, clrRed);
                  }
                  else if(OrderType() == OP_SELL)
                  {
                     ticket = OrderSend(Symbol(), OP_BUY, hedgeLot, Ask, Slippage, 
                                       OrderOpenPrice() - StopLoss * Point, 
                                       OrderOpenPrice() + TakeProfit * Point, 
                                       "Hedge", MagicNumber, 0, clrGreen);
                  }
                  
                  if(ticket > 0)
                  {
                     hedgedPositions[OrderTicket()] = true;
                     Print("Hedge position opened successfully for order #", OrderTicket(), 
                           " with adjusted lot size: ", hedgeLot);
                  }
                  else
                  {
                     Print("Error opening hedge position: ", GetLastError());
                     if(CloseOnHedgeFailure)
                     {
                        OrderClose(OrderTicket(), OrderLots(), 
                                  OrderType() == OP_BUY ? Bid : Ask, 
                                  Slippage, clrRed);
                        Print("Closed original position due to hedge failure");
                     }
                  }
               }
            }
         }
      }
   }
   
   // Print trade information periodically
   static datetime lastPrintTime = 0;
   if(TimeCurrent() - lastPrintTime >= 3600) // Print every hour
   {
      PrintTradeInfo();
      lastPrintTime = TimeCurrent();
   }
}

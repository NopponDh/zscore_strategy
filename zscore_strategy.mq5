//+------------------------------------------------------------------+
//|                                PairTrading_Multi_ZScore_V5_1.mq5 |
//|                                Copyright 2026, AI Assistant      |
//|                                Version: 5.1 - Safe Aggressive    |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>

//--- Settings
input group "=== Global Settings ==="
input double    InpProfitTargetPct = 10.0;    // เป้ากำไรล้างพอร์ตทั้งหมด (%)
input int       InpMagic           = 777999;  
input bool      InpFastBT          = true;    // true = เข้าออเดอร์เฉพาะแท่งใหม่ H4

input group "=== Z-Score Strategy (H4) ==="
input double    InpZEntry     = 2.2;         
input double    InpZStep      = 0.6;         
input int       InpLookback   = 300;         

input group "=== Risk Management ==="
input double    InpMaxLot         = 0.70;    // *** ปรับลดลงตามคำขอ (จาก 0.90 -> 0.70)
input int       InpMaxLayers      = 5;       
input double    InpMinMarginLevel = 1500.0;  
input double    InpTargetPer001   = 2.0;     

input group "=== 20 High Correlation Pairs (Unique Combinations) ==="
input string P1A="AUDUSD",P1B="NZDUSD";   input string P2A="EURUSD",P2B="GBPUSD";
input string P3A="EURJPY",P3B="GBPJPY";   input string P4A="AUDJPY",P4B="NZDJPY";
input string P5A="CADJPY",P5B="CHFJPY";   input string P6A="EURCAD",P6B="GBPCAD";
input string P7A="EURAUD",P7B="GBPAUD";   input string P8A="AUDCAD",P8B="NZDCAD";
input string P9A="EURCHF",P9B="GBPCHF";   input string P10A="GBPNZD",P10B="EURNZD";
input string P11A="AUDCHF",P11B="NZDCHF";  input string P12A="EURGBP",P12B="CADCHF";
input string P13A="USDCAD",P13B="USDCHF";  input string P14A="USDJPY",P14B="AUDNZD";
input string P15A="EURGBP",P15B="EURCHF";  input string P16A="CADCHF",P16B="AUDCHF";
input string P17A="GBPNZD",P17B="GBPAUD";  input string P18A="NZDCAD",P18B="NZDCHF";
input string P19A="AUDCAD",P19B="AUDCHF";  input string P20A="EURJPY",P20B="CHFJPY";

//--- Global Variables
CTrade trade;
struct PairData {
   string sA; string sB;
   double lastZ;
   int    id; 
   bool   isActive;
};

PairData MyPairs[20]; 
double   BaseEquity = 0; 
datetime GlobalLastBar = 0;

//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(InpMagic);
   BaseEquity = AccountInfoDouble(ACCOUNT_EQUITY); 
   for(int i=0; i<20; i++) MyPairs[i].id = i;
   
   InitPair(0, P1A, P1B);   InitPair(1, P2A, P2B);   InitPair(2, P3A, P3B);   InitPair(3, P4A, P4B);
   InitPair(4, P5A, P5B);   InitPair(5, P6A, P6B);   InitPair(6, P7A, P7B);   InitPair(7, P8A, P8B);
   InitPair(8, P9A, P9B);   InitPair(9, P10A, P10B);  InitPair(10, P11A, P11B); InitPair(11, P12A, P12B);
   InitPair(12, P13A, P13B); InitPair(13, P14A, P14B); InitPair(14, P15A, P15B); InitPair(15, P16A, P16B);
   InitPair(16, P17A, P17B); InitPair(17, P18A, P18B); InitPair(18, P19A, P19B); InitPair(19, P20A, P20B);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick() {
   if(_Period != PERIOD_H4) { Comment("!!! PLEASE USE H4 !!!"); return; }
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   if(currentEquity >= BaseEquity + (BaseEquity * (InpProfitTargetPct / 100.0))) {
      CloseAllEverything();
      BaseEquity = currentEquity; return;
   }
   
   CheckSpecificPairProfits(currentEquity); 

   datetime currentBar = iTime(_Symbol, PERIOD_H4, 0);
   bool isNewBar = (currentBar != GlobalLastBar);
   if(InpFastBT && !isNewBar) return; 
   GlobalLastBar = currentBar;

   // ระบบ Dynamic Lot ปรับตาม Equity แต่ไม่เกิน 0.70
   double dynamicLot  = MathMax(0.01, MathFloor(currentEquity / 1000.0) * 0.01);
   if(dynamicLot > InpMaxLot) dynamicLot = InpMaxLot; 
   double targetUSD = (dynamicLot / 0.01) * InpTargetPer001;

   for(int i=0; i<20; i++) {
      if(MyPairs[i].isActive) HandlePairLogic(MyPairs[i], dynamicLot, targetUSD);
   }
}

//+------------------------------------------------------------------+
void HandlePairLogic(PairData &p, double lot, double target) {
   int count=0; double profit=0;
   GetPairStatusByID(p.id, count, profit);

   if(count > 0 && profit >= target) {
      ClosePairByID(p.id);
      p.lastZ = 0; return;
   }

   double currentZ = CalculateZScore(p.sA, p.sB);
   if(currentZ == 999) return;
   if(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) < InpMinMarginLevel && AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) > 0) return;

   if(count == 0) {
      if(MathAbs(currentZ) >= InpZEntry) {
         if(OpenPairWithID(p, currentZ, lot)) p.lastZ = currentZ;
      }
   } else if(count < InpMaxLayers * 2) {
      if(MathAbs(currentZ - p.lastZ) >= InpZStep) {
         bool isExpanding = (p.lastZ > 0 && currentZ > p.lastZ) || (p.lastZ < 0 && currentZ < p.lastZ);
         if(isExpanding) {
            if(OpenPairWithID(p, currentZ, lot)) p.lastZ = currentZ;
         }
      }
   }
}

void GetPairStatusByID(int id, int &count, double &profit) {
   string tag = "PID:" + IntegerToString(id);
   count = 0; profit = 0;
   for(int i=PositionsTotal()-1; i>=0; i--) {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC) == InpMagic) {
         if(PositionGetString(POSITION_COMMENT) == tag) {
            count++;
            profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);
         }
      }
   }
}

bool OpenPairWithID(PairData &p, double z, double lot) {
   string tag = "PID:" + IntegerToString(p.id);
   double stepA = SymbolInfoDouble(p.sA,SYMBOL_VOLUME_STEP);
   double stepB = SymbolInfoDouble(p.sB,SYMBOL_VOLUME_STEP);
   double lA = MathFloor(lot/stepA)*stepA; double lB = MathFloor(lot/stepB)*stepB;
   bool r1, r2;
   if(z > 0) { r1 = trade.Sell(lA, p.sA, 0, 0, 0, tag); r2 = trade.Buy(lB, p.sB, 0, 0, 0, tag); }
   else      { r1 = trade.Buy(lA, p.sA, 0, 0, 0, tag); r2 = trade.Sell(lB, p.sB, 0, 0, 0, tag); }
   return (r1 || r2);
}

void ClosePairByID(int id) {
   string tag = "PID:" + IntegerToString(id);
   for(int i=PositionsTotal()-1; i>=0; i--) {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC) == InpMagic) {
         if(PositionGetString(POSITION_COMMENT) == tag) trade.PositionClose(t);
      }
   }
}

double CalculateZScore(string s1, string s2) {
   double c1[], c2[];
   ArraySetAsSeries(c1,true); ArraySetAsSeries(c2,true);
   if(CopyClose(s1,PERIOD_H4,0,InpLookback,c1)<InpLookback || CopyClose(s2,PERIOD_H4,0,InpLookback,c2)<InpLookback) return 999;
   double sum=0; for(int i=0; i<InpLookback; i++) sum += c1[i]/c2[i];
   double mean = sum/InpLookback;
   double sq_sum = 0; for(int i=0; i<InpLookback; i++) sq_sum += MathPow((c1[i]/c2[i])-mean, 2);
   double sd = MathSqrt(sq_sum/InpLookback);
   return (sd == 0) ? 999 : ((c1[0]/c2[0])-mean)/sd;
}

void CheckSpecificPairProfits(double eq) {
   double dLot = MathMax(0.01, MathFloor(eq / 1000.0) * 0.01);
   if(dLot > InpMaxLot) dLot = InpMaxLot;
   double target = (dLot / 0.01) * InpTargetPer001;
   for(int i=0; i<20; i++) {
      int count=0; double profit=0;
      GetPairStatusByID(i, count, profit);
      if(count > 0 && profit >= target) ClosePairByID(i);
   }
}

void InitPair(int index, string a, string b) {
   if(a == "" || b == "") { MyPairs[index].isActive = false; return; }
   MyPairs[index].sA = a; MyPairs[index].sB = b; MyPairs[index].isActive = true;
}

void CloseAllEverything() {
   for(int i=PositionsTotal()-1; i>=0; i--) {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC) == InpMagic) trade.PositionClose(t);
   }
}
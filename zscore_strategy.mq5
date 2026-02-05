//+------------------------------------------------------------------+
//|                                  PairTrading_Multi_ZScore_NoGold.mq5|
//|                                   Copyright 2026, AI Assistant    |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>

//--- Settings
input group "=== Global Equity Milestone ==="
input double   InpProfitTargetPct = 10.0;    // กำไรพอร์ตเพิ่ม 10% ให้ปิดเริ่มใหม่

input group "=== Z-Score Strategy (H4) ==="
input double   InpZEntry     = 2.2;         // จุดเริ่มไม้แรก (Z-Score)
input double   InpZStep      = 0.6;         // จุดเข้าไม้แก้
input int      InpLookback   = 300;       
input int      InpMagic      = 999222;

input group "=== Risk Management ==="
input double   InpMaxLot     = 0.50;        // จำกัด Lot สูงสุดต่อไม้เพื่อความปลอดภัย

input group "=== Pairs Selection (รองรับสูงสุด 20 คู่) ==="
input string   P1A = "AUDUSD", P1B = "NZDUSD";
input string   P2A = "EURUSD", P2B = "GBPUSD";
input string   P3A = "EURJPY", P3B = "GBPJPY";
input string   P4A = "AUDJPY", P4B = "NZDJPY";
input string   P5A = "CADJPY", P5B = "CHFJPY";
input string   P6A = "EURCAD", P6B = "GBPCAD";
input string   P7A = "EURAUD", P7B = "GBPAUD";
input string   P8A = "AUDCAD", P8B = "NZDCAD";
input string   P9A = "EURCHF", P9B = "GBPCHF";
input string   P10A = "USDCAD", P10B = "USDCHF";
input string   P11A = "EURGBP", P11B = "EURNZD";
input string   P12A = "GBPNZD", P12B = "GBPAUD";
input string   P13A = "AUDCHF", P13B = "NZDCHF";

CTrade trade;
struct PairData {
   string sA; string sB;
   double lastZ; double currentZ;
   datetime lastTradeBar;
   bool isActive;
};

PairData MyPairs[20]; 
double   BaseEquity = 0;

//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(InpMagic);
   BaseEquity = AccountInfoDouble(ACCOUNT_EQUITY); 
   
   InitPair(0, P1A, P1B);   InitPair(1, P2A, P2B);
   InitPair(2, P3A, P3B);   InitPair(3, P4A, P4B);
   InitPair(4, P5A, P5B);   InitPair(5, P6A, P6B);
   InitPair(6, P7A, P7B);   InitPair(7, P8A, P8B);
   InitPair(8, P9A, P9B);   InitPair(9, P10A, P10B);
   InitPair(10, P11A, P11B); InitPair(11, P12A, P12B);
   InitPair(12, P13A, P13B);
   
   Print("🚀 System Started. Dynamic Lot: 0.01 per 1000 Balance.");
   return(INIT_SUCCEEDED);
}

// (ฟังก์ชัน InitPair และ CalculateZScore คงเดิมตาม Logic ของคุณ)
void InitPair(int index, string a, string b) {
   if(a == "" || b == "") { MyPairs[index].isActive = false; return; }
   string forbidden[] = {"XAU", "GOLD", "XAG", "SILVER", "XPT", "XPD"};
   for(int i=0; i<ArraySize(forbidden); i++) {
      if(StringFind(a, forbidden[i]) >= 0 || StringFind(b, forbidden[i]) >= 0) {
         Print("⚠️ Blocked Precious Metal: ", a, " / ", b);
         MyPairs[index].isActive = false;
         return;
      }
   }
   MyPairs[index].sA = a; MyPairs[index].sB = b;
   MyPairs[index].isActive = true;
}

//+------------------------------------------------------------------+
void OnTick() {
   if(_Period != PERIOD_H4) { Comment("!!! PLEASE USE H4 TIMEFRAME !!!"); return; }

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance       = AccountInfoDouble(ACCOUNT_BALANCE);
   double targetEquity  = BaseEquity + (BaseEquity * (InpProfitTargetPct / 100.0));

   // --- ส่วนคำนวณ Dynamic Lot ทุกๆ 1000 เพิ่ม 0.01 ---
   double dynamicLot = MathFloor(balance / 1000.0) * 0.01;
   if(dynamicLot < 0.01) dynamicLot = 0.01; 
   if(dynamicLot > InpMaxLot) dynamicLot = InpMaxLot; // จำกัดความเสี่ยงไม่ให้เกิน MaxLot

   // เป้ากำไรต่อชุด (ปรับตามขนาด Lot)
   double dynamicTargetUSD = (dynamicLot / 0.01) * 1.5; 

   if(currentEquity >= targetEquity) {
      CloseAllEverything();
      BaseEquity = currentEquity; 
      Print("🎯 MILESTONE HIT! New Base: ", BaseEquity);
      return;
   }

   string monitor = "--- Global Currency Z-Score Sniper (H4) ---\n";
   monitor += "Equity: " + DoubleToString(currentEquity, 2) + " / Target: " + DoubleToString(targetEquity, 2) + "\n";
   monitor += "Current Lot Size: " + DoubleToString(dynamicLot, 2) + "\n";
   monitor += "------------------------------------\n";

   for(int i=0; i<20; i++) {
      if(MyPairs[i].isActive) {
         HandlePairLogic(MyPairs[i], dynamicLot, dynamicTargetUSD);
         monitor += MyPairs[i].sA + "/" + MyPairs[i].sB + " | Z: " + DoubleToString(MyPairs[i].currentZ, 2) + "\n";
      }
   }
   Comment(monitor);
}

//+------------------------------------------------------------------+
void HandlePairLogic(PairData &p, double lot, double target) {
   double pProfit = 0; int pCount = 0;
   for(int i=PositionsTotal()-1; i>=0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == InpMagic) {
         string sym = PositionGetString(POSITION_SYMBOL);
         if(sym == p.sA || sym == p.sB) {
            pCount++;
            pProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         }
      }
   }

   if(pCount > 0 && pProfit >= target) {
      CloseSpecificPair(p.sA, p.sB);
      p.lastZ = 0; p.lastTradeBar = 0;
      return;
   }

   p.currentZ = CalculateZScore(p.sA, p.sB);
   if(p.currentZ == 999) return;

   datetime currentBar = iTime(p.sA, PERIOD_H4, 0);
   if(currentBar == p.lastTradeBar) return;

   if(pCount == 0) {
      if(MathAbs(p.currentZ) >= InpZEntry) {
         if(OpenPair(p, p.currentZ, lot)) p.lastTradeBar = currentBar;
      }
   } else {
      if(MathAbs(p.currentZ - p.lastZ) >= InpZStep) {
         if((p.lastZ > 0 && p.currentZ > p.lastZ) || (p.lastZ < 0 && p.currentZ < p.lastZ)) {
            if(OpenPair(p, p.currentZ, lot)) p.lastTradeBar = currentBar;
         }
      }
   }
}

double CalculateZScore(string s1, string s2) {
   double c1[], c2[];
   ArraySetAsSeries(c1,true); ArraySetAsSeries(c2,true);
   if(CopyClose(s1,PERIOD_H4,0,InpLookback,c1)<InpLookback || CopyClose(s2,PERIOD_H4,0,InpLookback,c2)<InpLookback) return 999;
   double r[], sum=0; ArrayResize(r, InpLookback);
   for(int i=0; i<InpLookback; i++) { 
      if(c2[i] == 0) continue;
      r[i] = c1[i]/c2[i]; sum += r[i]; 
   }
   double mean = sum/InpLookback;
   double sq_sum = 0;
   for(int i=0; i<InpLookback; i++) sq_sum += MathPow(r[i]-mean, 2);
   double sd = MathSqrt(sq_sum/InpLookback);
   return (sd == 0) ? 999 : (r[0]-mean)/sd;
}

bool OpenPair(PairData &p, double z, double lot) {
   bool res = false;
   double step = SymbolInfoDouble(p.sA, SYMBOL_VOLUME_STEP);
   double normalizedLot = MathFloor(lot/step)*step;
   
   if(z > 0) res = (trade.Sell(normalizedLot, p.sA) && trade.Buy(normalizedLot, p.sB));
   else      res = (trade.Buy(normalizedLot, p.sA) && trade.Sell(normalizedLot, p.sB));
   if(res) p.lastZ = z; 
   return res;
}

void CloseAllEverything() {
   for(int i=PositionsTotal()-1; i>=0; i--) trade.PositionClose(PositionGetTicket(i));
}

void CloseSpecificPair(string s1, string s2) {
   for(int i=PositionsTotal()-1; i>=0; i--) {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC) == InpMagic) {
         string s = PositionGetString(POSITION_SYMBOL);
         if(s == s1 || s == s2) trade.PositionClose(t);
      }
   }
}
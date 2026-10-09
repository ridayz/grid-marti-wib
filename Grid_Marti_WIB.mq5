//+------------------------------------------------------------------+
//| Grid_Marti_WIB.mq5 - Marti averaging follow-trend, WIB filter    |
//| L santai 0.01,0.02,0.03.. / agresif 0.10,0.20,0.30.. TP basket   |
//+------------------------------------------------------------------+
#property copyright "Ridwan Master Trader"
#property version   "2.3"
#include <Trade\Trade.mqh>
CTrade trade;

enum ENUM_RISK_MODE
  {
   RISK_SANTAI  = 0, // Santai 0.01,0.02,0.03..
   RISK_AGRESIF = 1  // Agresif 0.10,0.20,0.30..
  };

input ENUM_RISK_MODE InpRiskMode = RISK_SANTAI; // Mode Lot
input double InpStep       = 2.0;   // Step averaging ($)
input int    InpMaxLayers  = 10;    // Max layer per arah
input double InpBasketTP   = 3.0;   // TP basket ($) biar cepet close
input double InpMaxCandle  = 6.0;   // Filter spike: skip entry/layer jika range M1 > $ ini
input int    InpTrendBars  = 2;     // Entry ikut tren: N candle M1 searah
input bool   InpUseDailyTarget = false; // Daily target ON/OFF
input double InpDailyTarget = 1000.0;   // Target harian $
input bool   InpNoTradeWed = true;  // Libur Rabu: blokir entry baru
input bool   InpNoTradeFri = true;  // Libur Jumat: blokir entry baru
input int    InpWIBOffset  = 7;     // WIB = server+offset
input long   InpMagic      = 777060;
input bool   InpUseChartTheme = true; // Theme chart otomatis (dark + candle custom)
input color  InpBgColor    = C'0,0,0';       // Background hitam
input color  InpBullColor  = C'30,144,255';  // Bull biru (screenshot)
input color  InpBearColor  = C'255,165,0';   // Bear oranye (screenshot)

//+---------- Chart theme (dark + candle custom ala screenshot) ----------+
datetime g_lastTheme = 0;
void ApplyChartTheme(bool force=false)
{
   if(!InpUseChartTheme) return;
   if(!force && TimeCurrent() - g_lastTheme < 3) return;
   g_lastTheme = TimeCurrent();
   long cid = ChartID();
   bool ok = true;
   ok &= ChartSetInteger(cid, CHART_MODE, CHART_CANDLES);
   ok &= ChartSetInteger(cid, CHART_SHOW_GRID, 0); // grid garis-garis OFF
   ok &= ChartSetInteger(cid, CHART_COLOR_BACKGROUND, InpBgColor);
   ok &= ChartSetInteger(cid, CHART_COLOR_FOREGROUND, C'220,220,220');
   ok &= ChartSetInteger(cid, CHART_COLOR_GRID, C'30,30,30');
   ok &= ChartSetInteger(cid, CHART_COLOR_CHART_UP, InpBullColor);
   ok &= ChartSetInteger(cid, CHART_COLOR_CHART_DOWN, InpBearColor);
   ok &= ChartSetInteger(cid, CHART_COLOR_CHART_LINE, C'0,255,0');
   ok &= ChartSetInteger(cid, CHART_COLOR_CANDLE_BULL, InpBullColor);
   ok &= ChartSetInteger(cid, CHART_COLOR_CANDLE_BEAR, InpBearColor);
   ok &= ChartSetInteger(cid, CHART_COLOR_BID, C'150,150,150');
   ok &= ChartSetInteger(cid, CHART_COLOR_ASK, C'150,150,150');
   ok &= ChartSetInteger(cid, CHART_COLOR_VOLUME, InpBullColor);
   ok &= ChartSetInteger(cid, CHART_SHOW_VOLUMES, CHART_VOLUME_HIDE);
   ChartRedraw(cid);
   PrintFormat("GW Theme v2.3 applied ok=%d bull=%d bear=%d bg=%d grid=OFF",
               ok, InpBullColor, InpBearColor, InpBgColor);
}

string g_status = "";
//+---------- HUD (darkmode) ----------+
void HudDel(){ for(int i = ObjectsTotal(0) - 1; i >= 0; i--){ string n = ObjectName(0, i); if(StringFind(n, "GW_HUD_") == 0) ObjectDelete(0, n); } }
void HudText(string n, string t, int x, int y, color c, int fs = 9)
{
   if(ObjectFind(0, n) < 0)
   {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_ZORDER, 100);
   }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, fs);
   ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
   ObjectSetString(0, n, OBJPROP_TEXT, t);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
}
void HudBG()
{
   string n = "GW_HUD_BG";
   if(ObjectFind(0, n) < 0)
   {
      ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_ZORDER, 90);
   }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, 8);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, 24);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, 300);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, 252);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, C'15,17,25');
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_COLOR, C'60,60,90');
   ObjectSetInteger(0, n, OBJPROP_BACK, false);
}
// stat persisten via GlobalVariable (selamat dari recompile/reattach)
string GV(string k){ return("GWIB_" + IntegerToString(InpMagic) + "_" + k); }
double GVGet(string k){ return(GlobalVariableCheck(GV(k)) ? GlobalVariableGet(GV(k)) : 0); }
void GVSet(string k, double v){ GlobalVariableSet(GV(k), v); }
string WIBDay()
{
   MqlDateTime dt; TimeToStruct(GetWIBTime(), dt);
   return(StringFormat("%04d%02d%02d", dt.year, dt.mon, dt.day));
}
void HudDraw(int b, int s, double flt, double closedToday)
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   string day = WIBDay();
   // reset harian
   if(GVGet("day") != StringToDouble(day)) { GVSet("day", StringToDouble(day)); GVSet("peakD", eq); GVSet("ddD", 0); }
   if(GVGet("peakD") == 0) GVSet("peakD", eq);
   if(GVGet("peakA") == 0) GVSet("peakA", eq);
   if(eq > GVGet("peakD")) GVSet("peakD", eq);
   if(eq > GVGet("peakA")) GVSet("peakA", eq);
   double ddD = MathMax(0, GVGet("peakD") - eq);
   double ddA = MathMax(0, GVGet("peakA") - eq);
   if(ddD > GVGet("ddD")) GVSet("ddD", ddD);
   if(ddA > GVGet("ddA")) GVSet("ddA", ddA);
   if(b > GVGet("maxB")) GVSet("maxB", b);
   if(s > GVGet("maxS")) GVSet("maxS", s);
   double pnl = closedToday + flt;
   color cFlt = (flt >= 0 ? C'0,210,110' : C'235,70,70');
   color cPnl = (pnl >= 0 ? C'0,210,110' : C'235,70,70');
   HudBG();
   int x0 = 20, y = 34, dy = 22;
   HudText("GW_HUD_T", "GRID WIB HUD", x0, y, C'168,85,247', 11); y += dy + 2;
   HudText("GW_HUD_0", StringFormat("Balance     $%12.2f", bal), x0, y, C'225,225,235'); y += dy;
   HudText("GW_HUD_1", StringFormat("Floating    $%+12.2f", flt), x0, y, cFlt); y += dy;
   HudText("GW_HUD_2", StringFormat("Layer B/S   %d / %d  (max %d/%d)", b, s, (int)GVGet("maxB"), (int)GVGet("maxS")), x0, y, C'0,200,220'); y += dy;
   HudText("GW_HUD_3", StringFormat("Basket TP   $%+.2f / lock $%.1f", flt, InpBasketTP), x0, y, C'250,200,80'); y += dy;
   HudText("GW_HUD_4", StringFormat("Last TP     %s", GVGet("lastTPt") > 0 ? StringFormat("+$%.2f", GVGet("lastTP")) : "-"), x0, y, C'0,210,110'); y += dy;
   HudText("GW_HUD_5", StringFormat("Live PNL    $%+12.2f (hari)", pnl), x0, y, cPnl); y += dy;
   HudText("GW_HUD_6", StringFormat("DD hari     -$%.2f", GVGet("ddD")), x0, y, C'235,70,70'); y += dy;
   HudText("GW_HUD_7", StringFormat("DD max      -$%.2f", GVGet("ddA")), x0, y, C'235,70,70'); y += dy;
   HudText("GW_HUD_8", g_status, x0, y, C'150,150,170', 8);
}

double EffBase(){ return(InpRiskMode==RISK_AGRESIF ? 0.10 : 0.01); }
double EffAdd(){ return(InpRiskMode==RISK_AGRESIF ? 0.10 : 0.01); }

double LayerLot(int l)
  {
   double lot = EffBase() + EffAdd()*(l-1); // L1=base, L2=base+add...
   double mn,mx,st;
   SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN,mn);
   SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX,mx);
   SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP,st);
   lot=MathMin(lot,5.0);
   lot=MathMax(mn,MathMin(mx,lot));
   if(st>0) lot=MathFloor(lot/st+1e-8)*st;
   return(NormalizeDouble(lot,2));
  }

datetime GetWIBTime(){ return((datetime)(TimeTradeServer()+InpWIBOffset*3600)); }
bool IsBlockedDay()
  {
   MqlDateTime dt; TimeToStruct(GetWIBTime(),dt); int dow=dt.day_of_week;
   if(dow==3 && InpNoTradeWed) return(true);
   if(dow==5 && InpNoTradeFri) return(true);
   return(false);
  }

void CntBS(int &b,int &s)
  {
   b=0; s=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong k=PositionGetTicket(i); if(!k) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) b++; else s++;
     }
  }

double BasketP()
  {
   double p=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong k=PositionGetTicket(i); if(!k) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      p+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
     }
   return(p);
  }

double ClosedToday()
  {
   datetime ds=(datetime)iTime(_Symbol,PERIOD_D1,0);
   HistorySelect(ds,TimeCurrent()+3600);
   double p=0; int n=HistoryDealsTotal();
   for(int i=n-1;i>=0;i--)
     {
      ulong tk=HistoryDealGetTicket(i); if(!tk) continue;
      if(HistoryDealGetString(tk,DEAL_SYMBOL)!=_Symbol) continue;
      if(HistoryDealGetInteger(tk,DEAL_MAGIC)!=InpMagic) continue;
      datetime dt=(datetime)HistoryDealGetInteger(tk,DEAL_TIME);
      if(dt<ds) continue;
      p+=HistoryDealGetDouble(tk,DEAL_PROFIT)+HistoryDealGetDouble(tk,DEAL_SWAP)+HistoryDealGetDouble(tk,DEAL_COMMISSION);
     }
   return(p);
  }

void CloseAll()
  {
   trade.SetExpertMagicNumber(InpMagic);
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong k=PositionGetTicket(i); if(!k) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      trade.PositionClose(k);
     }
  }

double AvgBuy()
  {
   double s=0,v=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong k=PositionGetTicket(i); if(!k) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      if(PositionGetInteger(POSITION_TYPE)!=POSITION_TYPE_BUY) continue;
      s+=PositionGetDouble(POSITION_PRICE_OPEN)*PositionGetDouble(POSITION_VOLUME);
      v+=PositionGetDouble(POSITION_VOLUME);
     }
   return(v>0?s/v:0);
  }

double AvgSell()
  {
   double s=0,v=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong k=PositionGetTicket(i); if(!k) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      if(PositionGetInteger(POSITION_TYPE)!=POSITION_TYPE_SELL) continue;
      s+=PositionGetDouble(POSITION_PRICE_OPEN)*PositionGetDouble(POSITION_VOLUME);
      v+=PositionGetDouble(POSITION_VOLUME);
     }
   return(v>0?s/v:0);
  }

bool IsSpike()
  {
   double h=iHigh(_Symbol,PERIOD_M1,1), l=iLow(_Symbol,PERIOD_M1,1);
   if(h<=0||l<=0) return(false);
   return((h-l)>=InpMaxCandle);
  }

int TrendDir()
  {
   int nb=MathMax(1,InpTrendBars), up=0, dn=0;
   for(int i=1;i<=nb;i++)
     {
      double o=iOpen(_Symbol,PERIOD_M1,i), c=iClose(_Symbol,PERIOD_M1,i);
      if(c<=0||o<=0) continue;
      if(c>o) up++; else if(c<o) dn++;
     }
   if(up==nb) return(1);
   if(dn==nb) return(-1);
   return(0);
  }

int OnInit(){ trade.SetExpertMagicNumber(InpMagic); g_lastTheme=0; ApplyChartTheme(true); return(INIT_SUCCEEDED); }
void OnDeinit(const int r){ HudDel(); Comment(""); }

void OnTick()
  {
   ApplyChartTheme(false); // paksa theme tiap ~3 detik (grid OFF + biru/oranye)
   if(IsBlockedDay()) // libur: hanya boleh TP close
     {
      int bb0,ss0; CntBS(bb0,ss0); double pf0=BasketP();
      if(bb0+ss0>0 && pf0>=InpBasketTP) { GVSet("lastTP",pf0); GVSet("lastTPt",TimeCurrent()); CloseAll(); }
      g_status = "LIBUR RABU/JUMAT (WIB)";
      HudDraw(bb0, ss0, pf0, ClosedToday());
      return;
     }
   if(InpUseDailyTarget && ClosedToday()>=InpDailyTarget) { g_status = "Daily target tercapai"; int db,ds; CntBS(db,ds); HudDraw(db, ds, BasketP(), ClosedToday()); return; }

   int b,s; CntBS(b,s); double bb=BasketP();

   if(b+s>0 && bb>=InpBasketTP) { GVSet("lastTP",bb); GVSet("lastTPt",TimeCurrent()); CloseAll(); g_status="BASKET DONE"; HudDraw(0,0,0,ClosedToday()); return; } // TP cepet, no SL/CL

   if(b>0 && b<InpMaxLayers)
     {
      double av=AvgBuy(); MqlTick t; SymbolInfoTick(_Symbol,t);
      if(!IsSpike() && t.bid <= av - InpStep)
        { trade.SetExpertMagicNumber(InpMagic); trade.Buy(LayerLot(b+1),_Symbol,0,0,0,"MARTI-BUY L"+IntegerToString(b+1)); }
     }
   if(s>0 && s<InpMaxLayers)
     {
      double av=AvgSell(); MqlTick t; SymbolInfoTick(_Symbol,t);
      if(!IsSpike() && t.ask >= av + InpStep)
        { trade.SetExpertMagicNumber(InpMagic); trade.Sell(LayerLot(s+1),_Symbol,0,0,0,"MARTI-SELL L"+IntegerToString(s+1)); }
     }
   if(b+s==0)
     {
      if(IsSpike()) return; // candle gede/spike: jangan entry, hemat layer
      int tr=TrendDir();
      trade.SetExpertMagicNumber(InpMagic);
      if(tr>0) trade.Buy(LayerLot(1),_Symbol,0,0,0,"MARTI-TREND BUY");
      else if(tr<0) trade.Sell(LayerLot(1),_Symbol,0,0,0,"MARTI-TREND SELL");
      else
        {
         MqlTick t; SymbolInfoTick(_Symbol,t);
         double h=iHigh(_Symbol,PERIOD_M1,1), l=iLow(_Symbol,PERIOD_M1,1);
         double mid=(h+l)/2, price=(t.bid+t.ask)/2;
         if(price>=mid) trade.Buy(LayerLot(1),_Symbol,0,0,0,"MARTI-FOLLOW BUY");
         else trade.Sell(LayerLot(1),_Symbol,0,0,0,"MARTI-FOLLOW SELL");
        }
     }
   g_status = "";
   HudDraw(b, s, bb, ClosedToday());
  }
//+------------------------------------------------------------------+

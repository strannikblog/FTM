//+------------------------------------------------------------------+
//|                                      Risk Manager Indicator v1.55    |
//|                    3-Level Dynamic Risk Management with Recovery Targets |
//|                    Dynamic Risk Output for Trade Manager Integration |
//|                    Static Override - Dual Protection Risk Management    |
//|                    Based on RISK_MANAGER_SYSTEM_LOGIC.md v2.0   |
//+------------------------------------------------------------------+
#property copyright "Risk Management Indicator"
#property link      ""
#property version   "1.55"
#property description "3-Level Dynamic Risk Management with Static Override Dual Protection"
#property indicator_chart_window
#property indicator_plots   0

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Risk Management Settings ==="
input double inpMaxRiskPercent = 2.0;           // Maximum Risk %
input double inpMinRiskPercent = 0.5;           // Minimum Risk %
input double inpRecoveryThreshold = 0.5;        // Recovery Multiplier (fixed at 0.5)
input bool inpAutoDetectTrades = true;          // Auto-detect new closed trades

input group "=== Static Override Settings ==="
input bool inpEnableStaticOverride = true;      // Enable Static Override protection
input double inpStaticThreshold1 = 5.0;         // DD threshold for level 1 (%)
input double inpStaticThreshold2 = 7.0;         // DD threshold for level 2 (%)
input double inpStaticThreshold3 = 10.0;        // DD threshold for trading halt (%)
input double inpStaticRisk1 = 2.0;              // Max risk below threshold 1 (%)
input double inpStaticRisk2 = 1.0;              // Max risk between threshold 1-2 (%)
input double inpStaticRisk3 = 0.5;              // Max risk between threshold 2-3 (%)

input group "=== Chart Control Settings ==="
input bool inpRunOnAllCharts = false;           // Run on all charts (false = single chart mode)
input string inpPreferredSymbol = "";           // Preferred symbol (empty = any symbol)

input group "=== Display Settings ==="
input color inpLabelBackgroundColor = C'240,240,240';  // Label background
input color inpLabelTextColor = C'50,50,50';            // Label text color
input int inpLabelX = 20;                               // Panel X position (pixels from left)
input int inpLabelY = 30;                               // Panel Y position (pixels from top)
input int inpFontSize = 9;                              // Font size
input bool inpShowDrawdown = true;                       // Show Drawdown Information
input bool inpShowRecoveryPercentages = false;           // Show Recovery Targets as Percentages

input group "=== Trade Planning Settings ==="
input double inpAccountSize = 100000.0;                // Account Size for Planning
input double inpMonthlyGoalPercent = 2.0;              // Monthly Goal Percentage
input int inpTradingDaysPerWeek = 5;                    // Trading Days Per Week
input bool inpShowDollarAmounts = true;                 // Show Dollar Amounts
input bool inpShowPercentages = true;                    // Show Percentages

//+------------------------------------------------------------------+
//| Risk Manager State Structure - Enhanced for Static Override     |
//+------------------------------------------------------------------+
struct RiskManagerState {
    // Three Risk Levels
    double maxRiskPercent;        // User defined (e.g., 2.0)
    double midRiskPercent;        // Calculated (50% of max, e.g., 1.0)
    double minRiskPercent;        // User defined (e.g., 0.5)
    double currentRiskPercent;    // Current active risk (one of the three levels)

    // Recovery Journey Variables
    double peakEquity;            // Highest equity ever reached
    double startingEquity;        // Equity after last losing trade (recovery start)
    double accumulatedProfit;     // Profit accumulated since last loss
    double currentLevelTarget;    // Target to reach immediate next level
    double maxLevelTarget;        // Total target to reach MAX level

    // Fixed Target Amounts for Display (stage-based logic)
    double targetMidToMax;        // Fixed amount needed from MID to MAX (for display reference)

    // Static Override Variables
    double currentDrawdown;        // Current drawdown percentage
    double staticRiskCeiling;      // Static risk cap based on drawdown
    double dynamicRiskPercent;     // Risk before static override applied
    bool tradingHalted;            // Trading disabled flag (DD ≥ 10%)

    // Trade Planning Variables (Manual inputs, not dynamic)
    double accountSize;           // Manual account size for planning
    double monthlyGoalPercent;    // Manual monthly goal percentage
    double monthlyGoalAmount;     // Calculated monthly goal amount (percentage of account)
    double weeklyGoalPercent;     // Calculated weekly goal percentage (monthly / 4)
    double weeklyGoalAmount;      // Calculated weekly goal amount
    double dailyGoalPercent;      // Calculated daily goal percentage (weekly / tradingDaysPerWeek)
    double dailyGoalAmount;       // Calculated daily goal amount
    double currentMonthPnL;       // Current month profit/loss
    double currentWeekPnL;        // Current week profit/loss
    double currentDayPnL;         // Current day profit/loss
    datetime monthStart;          // Start of current month
    datetime weekStart;           // Start of current week
    datetime dayStart;            // Start of current day

    // Trade Tracking
    int consecutiveLosses;        // Current loss streak
    datetime journeyStartTime;    // When current recovery journey started
    ulong lastProcessedTicket;    // Avoid reprocessing same trades
    string lastTradeType;          // "LOSS" or "PROFIT" for logging

    // System State
    string accountNumber;         // Account identifier
    datetime lastUpdateTime;      // Last state update
};

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
RiskManagerState g_state;
bool g_initialized = false;
bool g_shouldRun = false;
bool g_stateModified = false;
string g_labelName = "RiskManagerLabel";
string g_buttonName = "RiskManagerResetButton";
string g_riskOutputFileName = "RiskManager\\RiskManager_CurrentRisk.csv"; // Dynamic risk output file

//+------------------------------------------------------------------+
//| Static Override Core Functions                                    |
//+------------------------------------------------------------------+
double CalculateStaticCeiling(double drawdownPercent) {
    if(drawdownPercent >= inpStaticThreshold3) {
        return 0.0;      // Trading halted
    } else if(drawdownPercent >= inpStaticThreshold2) {
        return inpStaticRisk3;  // Emergency mode (e.g., 0.5%)
    } else if(drawdownPercent >= inpStaticThreshold1) {
        return inpStaticRisk2;  // Reduced mode (e.g., 1.0%)
    } else {
        return 999.0;    // No restriction (effectively unlimited)
    }
}

void ApplyStaticOverride(RiskManagerState &state) {
    if(!inpEnableStaticOverride) {
        state.staticRiskCeiling = 999.0;
        state.tradingHalted = false;
        return;
    }

    // Calculate current drawdown
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    state.currentDrawdown = (state.peakEquity > 0) ?
        ((state.peakEquity - currentEquity) / state.peakEquity) * 100 : 0;

    // Determine static ceiling
    double staticCap = CalculateStaticCeiling(state.currentDrawdown);
    state.staticRiskCeiling = staticCap;

    // Store dynamic risk before override (preserve original dynamic level)
    // dynamicRiskPercent should already contain the correct value from loss/recovery logic

    // Apply override
    if(staticCap == 0.0) {
        state.tradingHalted = true;
        state.currentRiskPercent = 0.0;
        Print("🛑 TRADING HALTED: Drawdown ", DoubleToString(state.currentDrawdown, 1),
              "% exceeds ", DoubleToString(inpStaticThreshold3, 1), "% limit");
    } else {
        double finalRisk = MathMin(state.currentRiskPercent, staticCap);

        if(finalRisk < state.dynamicRiskPercent) {
            Print("⚠️ STATIC OVERRIDE: Dynamic risk ", DoubleToString(state.dynamicRiskPercent, 1),
                  "% capped at ", DoubleToString(staticCap, 1), "% due to ",
                  DoubleToString(state.currentDrawdown, 1), "% drawdown");
        }

        state.currentRiskPercent = finalRisk;
        state.tradingHalted = false;
    }
}

string GetStaticOverrideStatusText() {
    if(!inpEnableStaticOverride) {
        return "Static Override: Disabled";
    }

    if(g_state.tradingHalted) {
        return "🛑 TRADING HALTED (DD ≥ " + DoubleToString(inpStaticThreshold3, 0) + "%)";
    }

    if(g_state.staticRiskCeiling < 999.0) {
        return "⚠️ STATIC CAP: " + DoubleToString(g_state.staticRiskCeiling, 1) + "%";
    }

    return "Static Override: Inactive (DD < " + DoubleToString(inpStaticThreshold1, 0) + "%)";
}

//+------------------------------------------------------------------+
//| Dynamic Risk Output Functions                                     |
//+------------------------------------------------------------------+
void UpdateRiskFile(double currentRiskPercent) {
    // Create directory if it doesn't exist
    if(!FolderCreate("RiskManager")) {
        Print("❌ Failed to create RiskManager directory for risk output file");
        return;
    }

    string csvData = StringFormat("%.6f,%s,%s",
        currentRiskPercent,
        TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
        TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS)
    );

    // Save to risk output file
    int fileHandle = FileOpen(g_riskOutputFileName, FILE_WRITE | FILE_CSV | FILE_ANSI);
    if(fileHandle != INVALID_HANDLE) {
        FileWrite(fileHandle, csvData);
        FileClose(fileHandle);

        // Debug message clearly stating risk % has been logged
        Print("🔄 RISK % LOGGED: ", DoubleToString(currentRiskPercent, 1), "% has been written to file for Trade Manager");
        Print("📁 Risk output file: ", g_riskOutputFileName);
        Print("⏰ Timestamp: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));

    } else {
        Print("❌ Failed to update risk output file: ", g_riskOutputFileName);
    }
}

//+------------------------------------------------------------------+
//| State Serialization Functions - Enhanced for Static Override     |
//+------------------------------------------------------------------+
string StateToCsv(const RiskManagerState &state) {
    return StringFormat(
        "%.6f,%.6f,%.6f,%.6f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.6f,%.6f,%.6f,%d,%d,%d,%d,%s,%llu,%s,%d",
        state.maxRiskPercent,
        state.midRiskPercent,
        state.currentRiskPercent,
        state.minRiskPercent,
        state.peakEquity,
        state.startingEquity,
        state.accumulatedProfit,
        state.currentLevelTarget,
        state.maxLevelTarget,
        state.targetMidToMax,
        state.accountSize,
        state.monthlyGoalPercent,
        state.currentDrawdown,
        state.staticRiskCeiling,
        state.dynamicRiskPercent,
        (int)state.monthStart,
        (int)state.weekStart,
        (int)state.dayStart,
        state.consecutiveLosses,
        state.lastTradeType,
        state.lastProcessedTicket,
        state.accountNumber,
        (int)state.lastUpdateTime
    );
}

bool CsvToState(const string csvStr, RiskManagerState &state) {
    string parts[];
    int count = StringSplit(csvStr, ',', parts);

    if(count != 25) {  // Updated count for new fields
        Print("❌ Invalid state file format. Expected 25 fields, got ", count);
        return false;
    }

    state.maxRiskPercent = StringToDouble(parts[0]);
    state.midRiskPercent = StringToDouble(parts[1]);
    state.currentRiskPercent = StringToDouble(parts[2]);
    state.minRiskPercent = StringToDouble(parts[3]);
    state.peakEquity = StringToDouble(parts[4]);
    state.startingEquity = StringToDouble(parts[5]);
    state.accumulatedProfit = StringToDouble(parts[6]);
    state.currentLevelTarget = StringToDouble(parts[7]);
    state.maxLevelTarget = StringToDouble(parts[8]);
    state.targetMidToMax = StringToDouble(parts[9]);
    state.accountSize = StringToDouble(parts[10]);
    state.monthlyGoalPercent = StringToDouble(parts[11]);
    state.currentDrawdown = StringToDouble(parts[12]);    // New field
    state.staticRiskCeiling = StringToDouble(parts[13]);  // New field
    state.dynamicRiskPercent = StringToDouble(parts[14]); // New field
    state.monthStart = (datetime)StringToInteger(parts[15]);
    state.weekStart = (datetime)StringToInteger(parts[16]);
    state.dayStart = (datetime)StringToInteger(parts[17]);
    state.consecutiveLosses = (int)StringToInteger(parts[18]);
    state.lastTradeType = parts[19];
    state.lastProcessedTicket = StringToInteger(parts[20]);
    state.accountNumber = parts[21];
    state.lastUpdateTime = (datetime)StringToInteger(parts[22]);

    // Initialize new fields if loading old state format
    if(state.currentDrawdown == 0.0 && state.staticRiskCeiling == 0.0) {
        state.tradingHalted = false;
        // Will be recalculated in ApplyStaticOverride
    }

    return true;
}

void SaveStateToFile(const RiskManagerState &state) {
    if(!g_stateModified) return;

    string csvData = StateToCsv(state);
    string filename = "RiskManager\\RiskManager_State.csv";

    // Create directory if it doesn't exist
    if(!FolderCreate("RiskManager")) {
        Print("❌ Failed to create RiskManager directory");
        return;
    }

    // Save to file
    int fileHandle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI);
    if(fileHandle != INVALID_HANDLE) {
        FileWrite(fileHandle, csvData);
        FileClose(fileHandle);
        g_stateModified = false;
    } else {
        Print("❌ Failed to save state to file: ", filename);
    }
}

bool LoadStateFromFile(RiskManagerState &state) {
    string filename = "RiskManager\\RiskManager_State.csv";

    // Try to read state file
    int fileHandle = FileOpen(filename, FILE_READ | FILE_CSV | FILE_ANSI);
    if(fileHandle == INVALID_HANDLE) {
        Print("📄 No existing state file found - initializing new state");
        return false;
    }

    string csvData;
    if(!FileIsEnding(fileHandle)) {
        csvData = FileReadString(fileHandle);
    }
    FileClose(fileHandle);

    if(csvData == "") {
        Print("⚠️ State file is empty - initializing new state");
        return false;
    }

    return CsvToState(csvData, state);
}

//+------------------------------------------------------------------+
//| Trade Planning Functions                                         |
//+------------------------------------------------------------------+
void InitializeTradePlanning(RiskManagerState &state) {
    // Initialize trade planning variables from user inputs
    state.accountSize = inpAccountSize;
    state.monthlyGoalPercent = inpMonthlyGoalPercent;
    state.monthlyGoalAmount = (state.monthlyGoalPercent / 100.0) * state.accountSize;
    state.weeklyGoalPercent = state.monthlyGoalPercent / 4.0;
    state.weeklyGoalAmount = (state.weeklyGoalPercent / 100.0) * state.accountSize;
    state.dailyGoalPercent = state.weeklyGoalPercent / inpTradingDaysPerWeek;
    state.dailyGoalAmount = (state.dailyGoalPercent / 100.0) * state.accountSize;

    // Set up time periods
    ResetTradePlanningPeriods(state);

    // Initialize P&L tracking
    state.currentMonthPnL = 0.0;
    state.currentWeekPnL = 0.0;
    state.currentDayPnL = 0.0;

    Print("📊 Trade Planning Initialized:");
    Print("   Account Size: $", DoubleToString(state.accountSize, 2));
    Print("   Monthly Goal: ", DoubleToString(state.monthlyGoalPercent, 1), "% ($", DoubleToString(state.monthlyGoalAmount, 2), ")");
    Print("   Weekly Goal: ", DoubleToString(state.weeklyGoalPercent, 2), "% ($", DoubleToString(state.weeklyGoalAmount, 2), ")");
    Print("   Daily Goal: ", DoubleToString(state.dailyGoalPercent, 2), "% ($", DoubleToString(state.dailyGoalAmount, 2), ")");
    Print("   Trading Days/Week: ", inpTradingDaysPerWeek);
    Print("   Recovery Display: ", inpShowRecoveryPercentages ? "Percentages" : "Dollar Amounts");
}

void ResetTradePlanningPeriods(RiskManagerState &state) {
    MqlDateTime timeStruct;
    TimeToStruct(TimeCurrent(), timeStruct);

    // Set month start (1st day of current month at 00:00)
    timeStruct.day = 1;
    timeStruct.hour = 0;
    timeStruct.min = 0;
    timeStruct.sec = 0;
    state.monthStart = StructToTime(timeStruct);

    // Set week start (Monday at 00:00)
    MqlDateTime currentTimeStruct;
    TimeToStruct(TimeCurrent(), currentTimeStruct);
    int dayOfWeek = currentTimeStruct.day_of_week;
    datetime mondayTime = TimeCurrent() - (dayOfWeek * 24 * 3600);
    TimeToStruct(mondayTime, timeStruct);
    timeStruct.hour = 0;
    timeStruct.min = 0;
    timeStruct.sec = 0;
    state.weekStart = StructToTime(timeStruct);

    // Set day start (today at 00:00)
    TimeToStruct(TimeCurrent(), timeStruct);
    timeStruct.hour = 0;
    timeStruct.min = 0;
    timeStruct.sec = 0;
    state.dayStart = StructToTime(timeStruct);
}

void UpdateTradePlanningPnL(RiskManagerState &state, double tradeProfit) {
    MqlDateTime currentTimeStruct;
    TimeToStruct(TimeCurrent(), currentTimeStruct);
    datetime currentDateTime = StructToTime(currentTimeStruct);

    // Check if periods need to be reset
    bool needPeriodReset = false;

    // Check for new month
    MqlDateTime monthStartStruct;
    TimeToStruct(state.monthStart, monthStartStruct);

    if(currentTimeStruct.mon != monthStartStruct.mon || currentTimeStruct.day != monthStartStruct.day) {
        // New month - reset monthly P&L
        state.currentMonthPnL = 0.0;
        state.monthStart = currentDateTime;
        needPeriodReset = true;
        Print("📅 New Month - Monthly P&L reset to $0");
    }

    // Simple week reset logic - reset if we're on Monday
    int currentDayOfWeek = currentTimeStruct.day_of_week;

    MqlDateTime weekStartStruct;
    TimeToStruct(state.weekStart, weekStartStruct);
    int weekStartDayOfWeek = weekStartStruct.day_of_week;

    // If current day is Monday and we haven't already updated this week
    if(currentDayOfWeek == 1 && weekStartDayOfWeek != 1) {
        // New week - reset weekly P&L
        state.currentWeekPnL = 0.0;
        state.weekStart = currentDateTime;
        needPeriodReset = true;
        Print("📅 New Week - Weekly P&L reset to $0");
    }

    // Check for new day
    MqlDateTime dayStartStruct;
    TimeToStruct(state.dayStart, dayStartStruct);

    if(currentTimeStruct.day != dayStartStruct.day || currentTimeStruct.mon != dayStartStruct.mon || currentTimeStruct.year != dayStartStruct.year) {
        // New day - reset daily P&L
        state.currentDayPnL = 0.0;
        state.dayStart = currentDateTime;
        needPeriodReset = true;
        Print("📅 New Day - Daily P&L reset to $0");
    }

    if(needPeriodReset) {
        // Also recalculate goals when periods reset
        state.weeklyGoalPercent = state.monthlyGoalPercent / 4.0;
        state.weeklyGoalAmount = (state.weeklyGoalPercent / 100.0) * state.accountSize;
        state.dailyGoalPercent = state.weeklyGoalPercent / inpTradingDaysPerWeek;
        state.dailyGoalAmount = (state.dailyGoalPercent / 100.0) * state.accountSize;
    }

    // Update P&L for all periods
    state.currentMonthPnL += tradeProfit;
    state.currentWeekPnL += tradeProfit;
    state.currentDayPnL += tradeProfit;

    Print("💰 Trade Planning P&L Updated:");
    Print("   Daily: $", DoubleToString(state.currentDayPnL, 2), " / Goal: $", DoubleToString(state.dailyGoalAmount, 2));
    Print("   Weekly: $", DoubleToString(state.currentWeekPnL, 2), " / Goal: $", DoubleToString(state.weeklyGoalAmount, 2));
    Print("   Monthly: $", DoubleToString(state.currentMonthPnL, 2), " / Goal: $", DoubleToString(state.monthlyGoalAmount, 2));
}


//+------------------------------------------------------------------+
//| Core Risk Management Functions                                   |
//+------------------------------------------------------------------+
void InitializeState(RiskManagerState &state) {
    // Three Risk Levels
    state.maxRiskPercent = inpMaxRiskPercent;
    state.midRiskPercent = inpMaxRiskPercent * 0.5;  // 50% of max
    state.minRiskPercent = inpMinRiskPercent;

    // Start at maximum risk level
    state.currentRiskPercent = inpMaxRiskPercent;

    // Recovery Journey Variables
    state.peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    state.startingEquity = state.peakEquity;
    state.accumulatedProfit = 0.0;
    state.currentLevelTarget = state.peakEquity;  // No recovery needed at max
    state.maxLevelTarget = state.peakEquity;
    state.targetMidToMax = 0.0; // No recovery targets at MAX level

    // Static Override initialization
    state.currentDrawdown = 0.0;
    state.staticRiskCeiling = inpEnableStaticOverride ? 999.0 : 999.0;
    state.dynamicRiskPercent = state.currentRiskPercent;
    state.tradingHalted = false;

    // Initialize Trade Planning
    InitializeTradePlanning(state);

    // Trade Tracking
    state.consecutiveLosses = 0;
    state.journeyStartTime = TimeCurrent();
    state.lastProcessedTicket = 0;
    state.lastTradeType = "INIT";
    state.accountNumber = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
    state.lastUpdateTime = TimeCurrent();

    // Apply static override to initial state
    ApplyStaticOverride(state);
    SaveStateToFile(state);

    // Initialize dynamic risk output file
    UpdateRiskFile(state.currentRiskPercent);

    Print("🆕 Risk Manager Initialized with Static Override:");
    Print("   MAX: ", DoubleToString(state.maxRiskPercent, 2), "%");
    Print("   MID: ", DoubleToString(state.midRiskPercent, 2), "%");
    Print("   MIN: ", DoubleToString(state.minRiskPercent, 2), "%");
    Print("   Starting at MAX level");
    Print("   Drawdown Display: ", inpShowDrawdown ? "Enabled" : "Disabled");
    Print("   Recovery Display: ", inpShowRecoveryPercentages ? "Percentages" : "Dollar Amounts");
    Print("   Static Override: ", inpEnableStaticOverride ? "Enabled" : "Disabled");
    Print("   Dynamic Risk Output: Enabled for Trade Manager integration");

    // Log initialization to spreadsheet
    LogTransactionToSpreadsheet(state, 0.0, "INIT");
}

//+------------------------------------------------------------------+
//| Chart Control Functions                                         |
//+------------------------------------------------------------------+
bool ShouldRunOnChart() {
    if(inpRunOnAllCharts) {
        return true;
    }

    if(inpPreferredSymbol != "") {
        if(StringCompare(_Symbol, inpPreferredSymbol, false) == 0) {
            return true;
        } else {
            return false;
        }
    }

    return true; // Default: let user control by not adding to multiple charts
}

//+------------------------------------------------------------------+
//| Transaction Logging Functions                                     |
//+------------------------------------------------------------------+
void LogTransactionToSpreadsheet(const RiskManagerState &state, double profit, string tradeType) {
    string fileName = "RiskManager\\RiskManager_Transactions_" + state.accountNumber + ".csv";
    string oldFileName = "RiskManager_Transactions_" + state.accountNumber + ".csv";

    // Try to open file to check if it exists and create header if needed
    int fileHandle = FileOpen(fileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ",");
    if(fileHandle == INVALID_HANDLE) {
        // File doesn't exist, create it with header
        fileHandle = FileOpen(fileName, FILE_WRITE | FILE_CSV | FILE_ANSI, ",");
        if(fileHandle != INVALID_HANDLE) {
            FileWriteString(fileHandle, "Date,Time,RiskLevel,Equity,Profit,TradeType,NextLevel,NextLevelTarget,MaxLevelTarget,StartingEquity,AccumulatedProfit,Drawdown,StaticCap\n");
            FileClose(fileHandle);
            Print("📊 Created transaction log: ", fileName);
        }
    } else {
        // File exists, check if it has header by reading first line
        string header = FileReadString(fileHandle);
        if(StringLen(header) == 0) {
            // Empty file, write header
            FileSeek(fileHandle, 0, SEEK_SET);
            FileWriteString(fileHandle, "Date,Time,RiskLevel,Equity,Profit,TradeType,NextLevel,NextLevelTarget,MaxLevelTarget,StartingEquity,AccumulatedProfit,Drawdown,StaticCap\n");
            Print("📊 Created transaction log: ", fileName);
        }
        FileClose(fileHandle);
    }

    // Append transaction (reopen file)
    fileHandle = FileOpen(fileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ",");
    if(fileHandle != INVALID_HANDLE) {
        datetime now = TimeCurrent();
        double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

        string currentLevelStr = DoubleToString(state.currentRiskPercent, 2) + "%";
        string nextLevelStr = "";
        string nextTargetStr = "";

        // Determine next level and targets
        if(state.dynamicRiskPercent == state.minRiskPercent) {
            nextLevelStr = DoubleToString(state.midRiskPercent, 2) + "%";
            nextTargetStr = "$" + DoubleToString(state.currentLevelTarget - currentEquity, 2);
        } else if(state.dynamicRiskPercent == state.midRiskPercent) {
            nextLevelStr = DoubleToString(state.maxRiskPercent, 2) + "%";
            nextTargetStr = "$" + DoubleToString(state.currentLevelTarget - currentEquity, 2);
        } else if(state.dynamicRiskPercent == state.maxRiskPercent) {
            nextLevelStr = "MAX";
            nextTargetStr = "At Target";
        }

        string maxTargetStr = "$" + DoubleToString(state.maxLevelTarget - currentEquity, 2);
        string startingEqStr = "$" + DoubleToString(state.startingEquity, 2);
        string accumulatedStr = "$" + DoubleToString(state.accumulatedProfit, 2);
        string drawdownStr = DoubleToString(state.currentDrawdown, 2) + "%";
        string staticCapStr = (state.staticRiskCeiling >= 999.0) ? "None" : DoubleToString(state.staticRiskCeiling, 1) + "%";

        FileWrite(fileHandle,
            TimeToString(now, TIME_DATE),
            TimeToString(now, TIME_SECONDS),
            currentLevelStr,
            DoubleToString(currentEquity, 2),
            DoubleToString(profit, 2),
            tradeType,
            nextLevelStr,
            nextTargetStr,
            maxTargetStr,
            startingEqStr,
            accumulatedStr,
            drawdownStr,
            staticCapStr
        );

        FileClose(fileHandle);

        Print("📊 Transaction logged: ", tradeType, " $", DoubleToString(profit, 2),
              " at ", currentLevelStr, " → Next: ", nextLevelStr);
    }
}

//+------------------------------------------------------------------+
//| Recovery Logic Functions - Based on System Logic Manual         |
//+------------------------------------------------------------------+
void ProcessNewTrades(RiskManagerState &state) {
    if(!inpAutoDetectTrades) return;

    // Get trade history
    HistorySelect(0, TimeCurrent());

    // Process new closed trades (reverse order to get newest first)
    for(int i = HistoryDealsTotal() - 1; i >= 0; i--) {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket == 0) continue;

        if(!HistoryDealSelect(ticket)) continue;

        // Skip if already processed
        if(ticket <= state.lastProcessedTicket) continue;

        // Check if it's a deal for current symbol and a closing deal
        string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
        long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);

        if(symbol != _Symbol) continue;
        if(entry != DEAL_ENTRY_OUT) continue; // Skip non-closing deals

        double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
        datetime closeTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);

        Print("📊 Processing closed trade #", ticket, " P/L: $", profit);

        // Process trade result
        ProcessTradeResult(state, profit, closeTime);
        state.lastProcessedTicket = ticket;
    }

    // Check for recovery progress
    CheckLevelProgress(state);
}

void ProcessTradeResult(RiskManagerState &state, double profit, datetime closeTime) {
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    string tradeType = profit < 0 ? "LOSS" : "PROFIT";

    // Update peak equity (new high watermark)
    if(currentEquity > state.peakEquity) {
        state.peakEquity = currentEquity;
        Print("🏈 New equity peak: $", state.peakEquity);
    }

    if(profit < 0) {
        // Loss detected - reduce risk level
        HandleLoss(state, profit, closeTime);
    } else if(profit > 0 && state.dynamicRiskPercent < state.maxRiskPercent) {
        // Profit detected while below max level - accumulate toward recovery
        state.accumulatedProfit += profit;
        Print("💰 Profit accumulated: $", DoubleToString(state.accumulatedProfit, 2));
        CheckLevelProgress(state);
    }

    // Update Trade Planning P&L
    UpdateTradePlanningPnL(state, profit);

    // Log transaction to spreadsheet
    LogTransactionToSpreadsheet(state, profit, tradeType);

    state.lastTradeType = tradeType;
    state.lastUpdateTime = TimeCurrent();
    g_stateModified = true;
}

void HandleLoss(RiskManagerState &state, double lossAmount, datetime closeTime) {
    state.consecutiveLosses++;
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

    Print("📉 Loss #", state.consecutiveLosses, " detected: -$", MathAbs(lossAmount),
          " at ", DoubleToString(state.dynamicRiskPercent, 2), "% risk level");

    // Move down one risk level (simplified logic)
    double previousRisk = state.dynamicRiskPercent;

    if(state.dynamicRiskPercent == state.maxRiskPercent) {
        // MAX → MID
        state.dynamicRiskPercent = state.midRiskPercent;
        Print("⚠️ Level Down: MAX(", DoubleToString(state.maxRiskPercent, 2), "%) → MID(",
              DoubleToString(state.midRiskPercent, 2), "%)");

    } else if(state.dynamicRiskPercent == state.midRiskPercent) {
        // MID → MIN
        state.dynamicRiskPercent = state.minRiskPercent;
        Print("⚠️ Level Down: MID(", DoubleToString(state.midRiskPercent, 2), "%) → MIN(",
              DoubleToString(state.minRiskPercent, 2), "%)");

    } else if(state.dynamicRiskPercent == state.minRiskPercent) {
        // Already at MIN - stay at MIN
        Print("⚠️ Already at MIN level (", DoubleToString(state.minRiskPercent, 2), "%) - staying");
    }

    // Only update journey if we actually moved down
    if(state.dynamicRiskPercent < previousRisk) {
        // Start new recovery journey from this losing trade
        state.startingEquity = currentEquity;
        state.journeyStartTime = closeTime;
        state.accumulatedProfit = 0.0;  // Reset accumulated profit on loss
        g_stateModified = true;

        Print("🆕 Starting NEW recovery journey from loss at $", DoubleToString(currentEquity, 2));

        // Calculate FIXED recovery targets based on risk level targets
        double accountEquity = currentEquity;

        if(state.dynamicRiskPercent == state.midRiskPercent) {
            // At MID: Need fixed amount to reach MAX
            double targetToMax = (state.maxRiskPercent * accountEquity * 0.01) * inpRecoveryThreshold;
            state.currentLevelTarget = currentEquity + targetToMax;
            state.maxLevelTarget = state.currentLevelTarget; // Same target since we're going to MAX
            state.targetMidToMax = targetToMax; // Store fixed reference amount

            Print("   MID Level Recovery Target:");
            Print("   Target to MAX (", DoubleToString(state.maxRiskPercent, 1), "%): $", DoubleToString(targetToMax, 2));
            Print("   Starting from: $", DoubleToString(currentEquity, 2));
            Print("   Target Equity: $", DoubleToString(state.currentLevelTarget, 2));

        } else if(state.dynamicRiskPercent == state.minRiskPercent) {
            // At MIN: Need fixed amount to reach MID, then fixed amount from MID to MAX
            double targetToMid = (state.midRiskPercent * accountEquity * 0.01) * inpRecoveryThreshold;
            double targetToMax = (state.maxRiskPercent * accountEquity * 0.01) * inpRecoveryThreshold;
            state.currentLevelTarget = currentEquity + targetToMid; // Target for next level (MID)
            state.maxLevelTarget = currentEquity + targetToMid + targetToMax; // Total target to reach MAX
            state.targetMidToMax = targetToMax; // Store fixed reference amount from MID to MAX

            Print("   MIN Level Recovery Target:");
            Print("   Target to MID (", DoubleToString(state.midRiskPercent, 1), "%): $", DoubleToString(targetToMid, 2));
            Print("   Target to MAX (", DoubleToString(state.maxRiskPercent, 1), "%): $", DoubleToString(targetToMax, 2));
            Print("   Starting from: $", DoubleToString(currentEquity, 2));
            Print("   Target Equity for MID: $", DoubleToString(state.currentLevelTarget, 2));
            Print("   Total Target for MAX: $", DoubleToString(state.maxLevelTarget, 2));
        }

        Print("🎯 Updated Recovery Targets:");
        Print("   Journey Started: $", DoubleToString(state.startingEquity, 2));
        Print("   Current Equity: $", DoubleToString(currentEquity, 2));
        Print("   Next Level Target: $", DoubleToString(state.currentLevelTarget, 2));
        Print("   Max Level Target: $", DoubleToString(state.maxLevelTarget, 2));
        Print("   Recovery Needed: $", DoubleToString(state.currentLevelTarget - currentEquity, 2));
    }

    // Apply static override after dynamic changes
    ApplyStaticOverride(state);

    // Update risk output file with final risk
    UpdateRiskFile(state.currentRiskPercent);
}

void CheckLevelProgress(RiskManagerState &state) {
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

    // Only check progress if we're below MAX level
    if(state.dynamicRiskPercent >= state.maxRiskPercent) {
        return;
    }

    double recoveryProfit = currentEquity - state.startingEquity;
    bool leveledUp = false;
    string levelUpReason = "";

    // Check for multi-level jumps from current position
    if(state.dynamicRiskPercent == state.minRiskPercent) {
        // At MIN (0.5%): Can jump to MID or directly to MAX

        if(currentEquity >= state.maxLevelTarget) {
            // Jump directly from MIN to MAX (multi-level jump)
            state.dynamicRiskPercent = state.maxRiskPercent;
            levelUpReason = "MIN → MAX (Multi-level jump)";
            leveledUp = true;

            Print("🚀 Multi-Level Jump: MIN(0.5%) → MAX(2.0%)! Surplus: $",
                  DoubleToString(currentEquity - state.maxLevelTarget, 2));

        } else if(currentEquity >= state.currentLevelTarget) {
            // Jump from MIN to MID
            state.dynamicRiskPercent = state.midRiskPercent;
            levelUpReason = "MIN → MID";
            leveledUp = true;

            // Update targets for reaching MAX from new MID position
            state.currentLevelTarget = state.maxLevelTarget; // Continue toward same MAX target
            // targetMidToMax remains the same (fixed reference amount)

            Print("📈 Level Up: MIN(0.5%) → MID(1.0%)!");
        }

    } else if(state.dynamicRiskPercent == state.midRiskPercent) {
        // At MID (1%): Can only jump to MAX

        if(currentEquity >= state.maxLevelTarget) {
            // Jump from MID to MAX
            state.dynamicRiskPercent = state.maxRiskPercent;
            levelUpReason = "MID → MAX";
            leveledUp = true;

            Print("📈 Level Up: MID(1.0%) → MAX(2.0%)!");
        }
    }

    // Handle level up actions
    if(leveledUp) {
        Print("🎯 Level Achievement: ", levelUpReason);
        Print("   Recovery Profit: $", DoubleToString(recoveryProfit, 2));
        Print("   Current Equity: $", DoubleToString(currentEquity, 2));

        // If we reached MAX, reset accumulated profit
        if(state.dynamicRiskPercent == state.maxRiskPercent) {
            state.accumulatedProfit = 0.0; // Reset at MAX
            state.consecutiveLosses = 0; // Reset loss streak
            state.currentLevelTarget = currentEquity;
            state.maxLevelTarget = currentEquity;

            Print("🏆 MAX Level Reached! Recovery complete.");
            Print("   Accumulated profit reset to $0");

        } else {
            // Continue accumulating toward MAX (no reset)
            Print("📊 Continuing toward MAX level");
            Print("   Still need: $", DoubleToString(state.maxLevelTarget - currentEquity, 2));
        }

        // Log level up to spreadsheet
        LogTransactionToSpreadsheet(state, recoveryProfit, "LEVEL_UP");

        // Apply static override before updating display
        ApplyStaticOverride(state);

        // Update risk output with capped risk if needed
        UpdateRiskFile(state.currentRiskPercent);
        g_stateModified = true;
    }
}

//+------------------------------------------------------------------+
//| Display Functions                                                |
//+------------------------------------------------------------------+
void CreateDisplay() {
    // Simple positioning like Forex Risk Manager
    int panelX = inpLabelX;
    int panelY = inpLabelY;
    int panelWidth = 270;  // Panel width
    int textPadding = 10;
    int lineHeight = 18;  // Increased spacing between lines

    // Calculate panel height based on whether drawdown and static override are shown
    int panelHeight;
    int labelCount;

    if(inpShowDrawdown && inpEnableStaticOverride) {
        panelHeight = 299; // Height with drawdown + static override line
        labelCount = 11;
    } else if(inpShowDrawdown || inpEnableStaticOverride) {
        panelHeight = 281; // Height with one additional line
        labelCount = 10;
    } else {
        panelHeight = 263; // Height without additional lines
        labelCount = 9;
    }

    // Create main panel (always use CORNER_LEFT_UPPER like Forex Risk Manager)
    if(ObjectCreate(0, g_labelName, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
        ObjectSetInteger(0, g_labelName, OBJPROP_XDISTANCE, panelX);
        ObjectSetInteger(0, g_labelName, OBJPROP_YDISTANCE, panelY);
        ObjectSetInteger(0, g_labelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, g_labelName, OBJPROP_XSIZE, panelWidth);
        ObjectSetInteger(0, g_labelName, OBJPROP_YSIZE, panelHeight);
        ObjectSetInteger(0, g_labelName, OBJPROP_BGCOLOR, inpLabelBackgroundColor);
        ObjectSetInteger(0, g_labelName, OBJPROP_BORDER_COLOR, clrGray);
        ObjectSetInteger(0, g_labelName, OBJPROP_BACK, true);
        ObjectSetInteger(0, g_labelName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    }

    // Create text labels based on configuration
    string lineNames[];
    ArrayResize(lineNames, labelCount);

    if(inpShowDrawdown && inpEnableStaticOverride) {
        string allNames[11] = {"_Title", "_DD", "_Risk", "_Targets", "_Detail1", "_Detail2", "_Detail3", "_TradePlanning1", "_TradePlanning2", "_TradePlanning3", "_StaticInfo"};
        ArrayCopy(lineNames, allNames);
    } else if(inpShowDrawdown) {
        string allNames[10] = {"_Title", "_DD", "_Risk", "_Targets", "_Detail1", "_Detail2", "_Detail3", "_TradePlanning1", "_TradePlanning2", "_TradePlanning3"};
        ArrayCopy(lineNames, allNames);
    } else if(inpEnableStaticOverride) {
        string allNames[10] = {"_Title", "_DD", "_Targets", "_Detail1", "_Detail2", "_Detail3", "_TradePlanning1", "_TradePlanning2", "_TradePlanning3", "_StaticInfo"};
        ArrayCopy(lineNames, allNames);
    } else {
        string allNames[9] = {"_Title", "_DD", "_Targets", "_Detail1", "_Detail2", "_Detail3", "_TradePlanning1", "_TradePlanning2", "_TradePlanning3"};
        ArrayCopy(lineNames, allNames);
    }

    for(int i = 0; i < labelCount; i++) {
        string labelName = g_labelName + lineNames[i];
        if(ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0)) {
            int textX = panelX + textPadding;
            int textY = panelY + textPadding + (i * lineHeight);

            ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, textX);
            ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, textY);
            ObjectSetInteger(0, labelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetString(0, labelName, OBJPROP_FONT, "Arial");
            ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, inpFontSize);
            ObjectSetInteger(0, labelName, OBJPROP_COLOR, inpLabelTextColor);
            ObjectSetInteger(0, labelName, OBJPROP_BACK, false);
        }
    }

    // Create reset button (positioned below panel)
    int buttonY = panelY + panelHeight + 5;
    if(ObjectCreate(0, g_buttonName, OBJ_BUTTON, 0, 0, 0)) {
        ObjectSetInteger(0, g_buttonName, OBJPROP_XDISTANCE, panelX);
        ObjectSetInteger(0, g_buttonName, OBJPROP_YDISTANCE, buttonY);
        ObjectSetInteger(0, g_buttonName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, g_buttonName, OBJPROP_XSIZE, panelWidth);
        ObjectSetInteger(0, g_buttonName, OBJPROP_YSIZE, 25);
        ObjectSetString(0, g_buttonName, OBJPROP_TEXT, "🔄 RESET RISK");
        ObjectSetString(0, g_buttonName, OBJPROP_FONT, "Arial Bold");
        ObjectSetInteger(0, g_buttonName, OBJPROP_FONTSIZE, 9);
        ObjectSetInteger(0, g_buttonName, OBJPROP_BGCOLOR, clrTomato);
        ObjectSetInteger(0, g_buttonName, OBJPROP_COLOR, clrWhite);
        ObjectSetInteger(0, g_buttonName, OBJPROP_BORDER_COLOR, clrRed);
    }
}

void UpdateDisplay() {
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double currentDD = g_state.peakEquity - currentEquity;
    double ddPercent = (g_state.peakEquity > 0) ? (currentDD / g_state.peakEquity) * 100 : 0;

    string currentLevel = GetCurrentLevelText();

    // Update drawdown in state
    g_state.currentDrawdown = ddPercent;

    string riskArrow = (g_state.currentRiskPercent < g_state.maxRiskPercent) ? "⬆️" : "✅";
    if(g_state.tradingHalted) {
        riskArrow = "🛑";
    }

    // Calculate remaining amounts for display
    double remainingToNext = 0.0;
    double remainingToMax = 0.0;
    double progressPercent = 0.0;

    if(g_state.dynamicRiskPercent < g_state.maxRiskPercent && g_state.currentLevelTarget > 0) {
        remainingToNext = MathMax(0.0, g_state.currentLevelTarget - currentEquity);
        remainingToMax = MathMax(0.0, g_state.maxLevelTarget - currentEquity);

        double totalNeeded = g_state.maxLevelTarget - g_state.startingEquity;
        if(totalNeeded > 0) {
            progressPercent = (g_state.accumulatedProfit / totalNeeded) * 100;
        }
    }

    // Always use detailed format
    ObjectSetString(0, g_labelName + "_Title", OBJPROP_TEXT, "🛡️ RISK MANAGER v1.55");

    // Set level information - show dynamic risk level
    string levelText = "Level: " + currentLevel + " (" + DoubleToString(g_state.dynamicRiskPercent, 1) + "%)";
    ObjectSetString(0, g_labelName + "_DD", OBJPROP_TEXT, levelText);

    int offsetIndex = 0;

    // Set drawdown information only if enabled
    if(inpShowDrawdown) {
        ObjectSetString(0, g_labelName + "_Risk", OBJPROP_TEXT, "Drawdown: $" + DoubleToString(MathAbs(currentDD), 2) + " (" + DoubleToString(ddPercent, 1) + "%)");
        ObjectSetString(0, g_labelName + "_Targets", OBJPROP_TEXT, "--------------");
        offsetIndex = 0;
    } else {
        // When drawdown is disabled, use the Targets label as the divider
        ObjectSetString(0, g_labelName + "_Targets", OBJPROP_TEXT, "--------------");
        offsetIndex = -1; // Adjust index since we're skipping the Risk label
    }

    if(g_state.dynamicRiskPercent < g_state.maxRiskPercent && remainingToNext > 0) {
        // Calculate remaining amounts using stage-based logic
        double remainingToMid = 0.0;
        double remainingToMaxFromMid = 0.0;
        double totalToMax = 0.0;

        // Calculate target amounts for percentage display
        double targetMinToMid = 0.0;
        double targetMidToMax = 0.0;

        if(g_state.dynamicRiskPercent == g_state.minRiskPercent) {
            // At MIN: Need to reach MID, then MAX
            remainingToMid = MathMax(0.0, g_state.currentLevelTarget - currentEquity);
            remainingToMaxFromMid = g_state.targetMidToMax; // Use stored fixed amount from MID to MAX
            totalToMax = MathMax(0.0, g_state.maxLevelTarget - currentEquity);

            // Calculate original target amounts for percentage display
            targetMinToMid = (g_state.midRiskPercent * g_state.startingEquity * 0.01) * inpRecoveryThreshold;
            targetMidToMax = (g_state.maxRiskPercent * g_state.startingEquity * 0.01) * inpRecoveryThreshold;

            if(inpShowRecoveryPercentages) {
                // Show as percentages
                double percentToMid = (targetMinToMid > 0) ? (remainingToMid / targetMinToMid) * 100 : 0;
                double percentToMax = (targetMidToMax > 0) ? (remainingToMaxFromMid / targetMidToMax) * 100 : 0;
                double percentTotal = ((targetMinToMid + targetMidToMax) > 0) ? (totalToMax / (targetMinToMid + targetMidToMax)) * 100 : 0;

                ObjectSetString(0, g_labelName + "_Detail1", OBJPROP_TEXT, "To MID (" + DoubleToString(g_state.midRiskPercent, 1) + "%): " + DoubleToString(percentToMid, 1) + "% remaining");
                ObjectSetString(0, g_labelName + "_Detail2", OBJPROP_TEXT, "To MAX (" + DoubleToString(g_state.maxRiskPercent, 1) + "%): " + DoubleToString(percentToMax, 1) + "% remaining");
                ObjectSetString(0, g_labelName + "_Detail3", OBJPROP_TEXT, "Total to MAX: " + DoubleToString(percentTotal, 1) + "% remaining");
            } else {
                // Show as dollar amounts
                ObjectSetString(0, g_labelName + "_Detail1", OBJPROP_TEXT, "To MID (" + DoubleToString(g_state.midRiskPercent, 1) + "%): $" + DoubleToString(remainingToMid, 2) + " remaining");
                ObjectSetString(0, g_labelName + "_Detail2", OBJPROP_TEXT, "To MAX (" + DoubleToString(g_state.maxRiskPercent, 1) + "%): $" + DoubleToString(remainingToMaxFromMid, 2) + " remaining");
                ObjectSetString(0, g_labelName + "_Detail3", OBJPROP_TEXT, "Total to MAX: $" + DoubleToString(totalToMax, 2) + " remaining");
            }

        } else if(g_state.dynamicRiskPercent == g_state.midRiskPercent) {
            // At MID: Only need to reach MAX
            remainingToMid = 0.0; // Already at MID level
            remainingToMaxFromMid = MathMax(0.0, g_state.maxLevelTarget - currentEquity);
            totalToMax = remainingToMaxFromMid;

            // Calculate original target amount for percentage display
            targetMidToMax = (g_state.maxRiskPercent * g_state.startingEquity * 0.01) * inpRecoveryThreshold;

            if(inpShowRecoveryPercentages) {
                // Show as percentages
                double percentToMax = (targetMidToMax > 0) ? (remainingToMaxFromMid / targetMidToMax) * 100 : 0;
                double percentTotal = (targetMidToMax > 0) ? (totalToMax / targetMidToMax) * 100 : 0;

                ObjectSetString(0, g_labelName + "_Detail1", OBJPROP_TEXT, "To MID (" + DoubleToString(g_state.midRiskPercent, 1) + "%): -");
                ObjectSetString(0, g_labelName + "_Detail2", OBJPROP_TEXT, "To MAX (" + DoubleToString(g_state.maxRiskPercent, 1) + "%): " + DoubleToString(percentToMax, 1) + "% remaining");
                ObjectSetString(0, g_labelName + "_Detail3", OBJPROP_TEXT, "Total to MAX: " + DoubleToString(percentTotal, 1) + "% remaining");
            } else {
                // Show as dollar amounts
                ObjectSetString(0, g_labelName + "_Detail1", OBJPROP_TEXT, "To MID (" + DoubleToString(g_state.midRiskPercent, 1) + "%): -");
                ObjectSetString(0, g_labelName + "_Detail2", OBJPROP_TEXT, "To MAX (" + DoubleToString(g_state.maxRiskPercent, 1) + "%): $" + DoubleToString(remainingToMaxFromMid, 2) + " remaining");
                ObjectSetString(0, g_labelName + "_Detail3", OBJPROP_TEXT, "Total to MAX: $" + DoubleToString(totalToMax, 2) + " remaining");
            }
        }
    } else {
        if(inpShowRecoveryPercentages) {
            ObjectSetString(0, g_labelName + "_Detail1", OBJPROP_TEXT, "To MID: -");
            ObjectSetString(0, g_labelName + "_Detail2", OBJPROP_TEXT, "To MAX (" + DoubleToString(g_state.maxRiskPercent, 1) + "%): Trading at MAX risk");
            ObjectSetString(0, g_labelName + "_Detail3", OBJPROP_TEXT, "Total to MAX: 0% remaining");
        } else {
            ObjectSetString(0, g_labelName + "_Detail1", OBJPROP_TEXT, "To MID: -");
            ObjectSetString(0, g_labelName + "_Detail2", OBJPROP_TEXT, "To MAX (" + DoubleToString(g_state.maxRiskPercent, 1) + "%): Trading at MAX risk");
            ObjectSetString(0, g_labelName + "_Detail3", OBJPROP_TEXT, "Total to MAX: $0.00");
        }
    }

    // Add second divider before trade planning
    ObjectSetString(0, g_labelName + "_TradePlanning1", OBJPROP_TEXT, "--------------");

    // Add trade planning information
    UpdateTradePlanningInMainDisplay();

    // Add static override information if enabled
    if(inpEnableStaticOverride) {
        ObjectSetString(0, g_labelName + "_StaticInfo", OBJPROP_TEXT, GetStaticOverrideStatusText());
    }
}

void UpdateTradePlanningInMainDisplay() {
    // Calculate current P&L progress percentages
    double weeklyProgress = (g_state.weeklyGoalAmount > 0) ? (g_state.currentWeekPnL / g_state.weeklyGoalAmount) * 100 : 0;
    double dailyProgress = (g_state.dailyGoalAmount > 0) ? (g_state.currentDayPnL / g_state.dailyGoalAmount) * 100 : 0;

    string dailyPnLText = "";
    string weeklyPnLText = "";

    // Format based on user preferences
    if(inpShowDollarAmounts && inpShowPercentages) {
        // Both features: "Daily Goal: $240 / $500 (48.0%)"
        dailyPnLText = StringFormat("Daily Goal: $%s / $%s (%.1f%%)",
            DoubleToString(g_state.currentDayPnL, 0),
            DoubleToString(g_state.dailyGoalAmount, 0),
            dailyProgress
        );

        weeklyPnLText = StringFormat("Weekly Goal: $%s / $%s (%.1f%%)",
            DoubleToString(g_state.currentWeekPnL, 0),
            DoubleToString(g_state.weeklyGoalAmount, 0),
            weeklyProgress
        );

    } else if(inpShowPercentages) {
        // Percentage only: "Daily Goal: 48.0% of 0.50%"
        dailyPnLText = StringFormat("Daily Goal: %.1f%% of %.2f%%",
            dailyProgress,
            g_state.dailyGoalPercent
        );

        weeklyPnLText = StringFormat("Weekly Goal: %.1f%% of %.2f%%",
            weeklyProgress,
            g_state.weeklyGoalPercent
        );

    } else if(inpShowDollarAmounts) {
        // Dollar amount only: "Daily Goal: $240 / $500"
        dailyPnLText = StringFormat("Daily Goal: $%s / $%s",
            DoubleToString(g_state.currentDayPnL, 0),
            DoubleToString(g_state.dailyGoalAmount, 0)
        );

        weeklyPnLText = StringFormat("Weekly Goal: $%s / $%s",
            DoubleToString(g_state.currentWeekPnL, 0),
            DoubleToString(g_state.weeklyGoalAmount, 0)
        );
    }

    // Update display lines (show Daily first, then Week)
    ObjectSetString(0, g_labelName + "_TradePlanning2", OBJPROP_TEXT, dailyPnLText);
    ObjectSetString(0, g_labelName + "_TradePlanning3", OBJPROP_TEXT, weeklyPnLText);
}

//+------------------------------------------------------------------+
//| Helper Functions                                                 |
//+------------------------------------------------------------------+
string GetCurrentLevelText() {
    if(g_state.dynamicRiskPercent == g_state.maxRiskPercent) {
        return "MAX";
    } else if(g_state.dynamicRiskPercent == g_state.midRiskPercent) {
        return "MID";
    } else if(g_state.dynamicRiskPercent == g_state.minRiskPercent) {
        return "MIN";
    } else {
        return "CUSTOM";
    }
}

//+------------------------------------------------------------------+
//| Manual Reset                                                     |
//+------------------------------------------------------------------+
void ManualReset() {
    Print("🔄 Manual reset requested");

    // Get current highest ticket number to prevent reprocessing old trades
    ulong highestTicket = 0;
    HistorySelect(0, TimeCurrent());
    for(int i = HistoryDealsTotal() - 1; i >= 0; i--) {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket > highestTicket) {
            highestTicket = ticket;
        }
    }

    InitializeState(g_state);
    // Set last processed ticket to current highest to skip all existing trades
    g_state.lastProcessedTicket = highestTicket;
    Print("🔄 Reset complete. Skipping trades up to ticket #", highestTicket);
    UpdateDisplay();
}

//+------------------------------------------------------------------+
//| Main Display Functions                                           |
//+------------------------------------------------------------------+
void DeleteDisplay() {
    ObjectDelete(0, g_labelName);
    ObjectDelete(0, g_buttonName);

    // Determine how many labels to delete based on configuration
    int labelCount;
    if(inpShowDrawdown && inpEnableStaticOverride) {
        labelCount = 11; // All labels including static info
    } else if(inpShowDrawdown || inpEnableStaticOverride) {
        labelCount = 10; // One additional line
    } else {
        labelCount = 9;  // Basic set only
    }

    // Delete the appropriate number of labels
    string lineNames[11] = {"_Title", "_DD", "_Risk", "_Targets", "_Detail1", "_Detail2", "_Detail3", "_TradePlanning1", "_TradePlanning2", "_TradePlanning3", "_StaticInfo"};

    for(int i = 0; i < labelCount; i++) {
        ObjectDelete(0, g_labelName + lineNames[i]);
    }
}

//+------------------------------------------------------------------+
//| Indicator Event Handlers                                         |
//+------------------------------------------------------------------+
int OnInit() {
    // Check if indicator should run on this chart
    g_shouldRun = ShouldRunOnChart();

    if(!g_shouldRun) {
        Print("🚫 Risk Manager Indicator disabled on ", _Symbol, " (chart control settings)");
        return(INIT_FAILED);
    }

    Print("🚀 Risk Manager Indicator v1.55 (Static Override Fixed) starting on ", _Symbol);

    // Try to load existing state
    if(!LoadStateFromFile(g_state)) {
        // No existing state, initialize new one
        InitializeState(g_state);
    } else {
        // Validate loaded state
        if(g_state.accountNumber != IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))) {
            Print("⚠️ State mismatch - reinitializing for new account");
            InitializeState(g_state);
        } else {
            Print("✓ Existing state loaded successfully");
            // Apply static override to loaded state
            ApplyStaticOverride(g_state);
            // Update risk output file with loaded state
            UpdateRiskFile(g_state.currentRiskPercent);
        }
    }

    // Create display elements
    CreateDisplay();
    UpdateDisplay();

    g_initialized = true;
    Print("✅ Risk Manager Indicator v1.55 initialized with Static Override and Dynamic Risk Output");

    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    Print("🛑 Risk Manager Indicator stopping...");

    // Save current state
    if(g_initialized) {
        if(g_stateModified) {
            SaveStateToFile(g_state);
        }
        DeleteDisplay();
    }

    Print("👋 Risk Manager Indicator stopped");
}

int OnCalculate(const int rates_total,
              const int prev_calculated,
              const datetime &time[],
              const double &open[],
              const double &high[],
              const double &low[],
              const double &close[],
              const long &tick_volume[],
              const long &real_volume[],
              const int &spread[]) {

    // Only process if this indicator instance should be running
    if(!g_shouldRun || !g_initialized) {
        return(rates_total);
    }

    // Apply static override on each tick (handles equity changes)
    double oldRiskPercent = g_state.currentRiskPercent;
    ApplyStaticOverride(g_state);

    // Update risk output if risk level changed due to drawdown
    if(g_state.currentRiskPercent != oldRiskPercent) {
        UpdateRiskFile(g_state.currentRiskPercent);
    }

    // Process new trades and update display
    ProcessNewTrades(g_state);
    UpdateDisplay();

    // Save state only if it was modified
    if(g_stateModified) {
        SaveStateToFile(g_state);
        g_stateModified = false;
    }

    return(rates_total);
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam) {

    // Only process events if this indicator instance should be running
    if(!g_shouldRun || !g_initialized) {
        return;
    }

    // Handle reset button click
    if(id == CHARTEVENT_OBJECT_CLICK && sparam == g_buttonName) {
        ManualReset();
        ObjectSetInteger(0, g_buttonName, OBJPROP_STATE, false);
        ChartRedraw();
    }

    // Handle chart property change (timeframe change, etc.)
    if(id == CHARTEVENT_CHART_CHANGE) {
        UpdateDisplay();
    }
}
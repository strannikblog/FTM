# Risk Manager System Logic Manual

**Version**: 1.0
**Date**: 2025-11-14
**Status**: Core System Logic - READ ONLY
**Modifications**: User Permission Required

---

## 📋 **System Overview**

A 3-level dynamic risk management system that reduces risk on losses and requires recovery targets to level back up to maximum risk. This document serves as the authoritative logic reference for all implementation decisions.

---

## 🎯 **Core Principles**

### **Risk Management Philosophy**
- Reduce risk immediately on losses
- Require proof of recovery through profit targets
- Progress through levels with accumulated gains
- Reset recovery progress only on losses or reaching maximum level

### **Design Intent**
Create a system that protects capital by automatically reducing exposure during drawdowns while requiring demonstrated recovery skill before increasing risk again.

---

## 📊 **Risk Levels Structure**

### **Three Risk Levels:**
- **MAX**: User-defined maximum risk (e.g., 2.0%)
- **MID**: 50% of MAX (calculated automatically)
- **MIN**: User-defined minimum risk (e.g., 0.5%)

### **Level Progression Rules:**
```
Loss Direction: MAX → MID → MIN
Profit Direction: MIN → MID → MAX
Multi-Level Jumps: Single profitable trade can skip intermediate levels
```

### **Risk Level Calculations:**
```cpp
midRiskPercent = maxRiskPercent * 0.5;
```

---

## 💰 **Recovery Logic - Core System**

### **Fundamental Rule: Recovery Journey Start**
**Each losing transaction starts a NEW recovery journey.**

- Starting Point: Account equity immediately after the losing trade
- Accumulated Profit: Reset to $0
- Journey Timestamp: Time of the losing trade

### **LEVEL-BASED RECOVERY TARGETS - COMPLETE SYSTEM**

**The system is completely level-based with exactly 3 levels and 2 transitions:**

#### **Level Structure:**
- **MAX**: User-defined maximum risk (e.g., 1.0% or 2.0%)
- **MID**: 50% of MAX (calculated automatically)
- **MIN**: User-defined minimum risk (e.g., 0.25% or 0.5%)

#### **Stage-Based Target Calculations:**
**Each transition requires 1/2 of the target level's risk percentage:**

1. **MIN → MID Transition**: Need 1/2 of MID risk amount
2. **MID → MAX Transition**: Need 1/2 of MAX risk amount

#### **Fixed Target Formula:**
```
Target Amount = (Target Level Risk % × Account Equity) × 0.5
```

#### **Key Rules:**
1. **Fixed Targets**: Recovery targets are FIXED amounts based on the equity when the recovery journey starts
2. **Stage-Based Display**: Each display line shows different information, not cumulative
3. **Level-Based Logic**: Everything depends on current level and target level

### **DISPLAY LOGIC - STAGE BASED SYSTEM**

**The display shows 3 pieces of information:**

1. **"To MID"**: Amount needed to reach MID level from current position
2. **"To MAX"**: Amount needed to reach MAX level from MID position (fixed reference)
3. **"Total to MAX"**: Total amount needed from CURRENT position to reach MAX

**Important**: "To MID" + "To MAX" ≠ "Total to MAX"
- "To MAX" always shows the amount needed FROM MID to MAX
- "Total to MAX" shows the amount needed FROM CURRENT position to MAX

### **COMPLETE EXAMPLES WITH DIFFERENT PARAMETER SETS**

#### **Example Set 1: Standard Parameters (MAX=2%, MIN=0.5%)**

**Account: $100,000 | MAX: 2% | MID: 1% | MIN: 0.5%**

**Fixed Targets:**
- MIN → MID: Need $500 (1% × $100,000 × 0.5)
- MID → MAX: Need $1,000 (2% × $100,000 × 0.5)

**Scenario 1A: Loss at MAX (2%) → Drop to MID (1%)**
- **Loss Amount**: $2,000 (2% risk trade)
- **New Equity**: $98,000
- **Current Level**: 1% (MID)
- **Starting Point**: $98,000

**Initial Display at MID:**
```
To MID: -                         ← Already at MID
To MAX (2%): $1,000.00 remaining   ← Amount needed from MID to MAX
Total to MAX: $1,000.00 remaining   ← Same since we're at MID
```

**After $300 profit:**
```
To MID: -
To MAX (2%): $700.00 remaining     ← $1,000 - $300
Total to MAX: $700.00 remaining
```

**Scenario 1B: Another Loss → Drop to MIN (0.5%)**
- **Loss Amount**: $1,000 (1% risk trade)
- **New Equity**: $97,000
- **Current Level**: 0.5% (MIN)
- **Starting Point**: $97,000 (reset to $0 accumulated)

**Display at MIN (2 levels to conquer):**
```
To MID: $500.00 remaining         ← Need $500 to reach MID
To MAX (2%): $1,000.00 remaining   ← Amount needed from MID to MAX (fixed)
Total to MAX: $1,500.00 remaining   ← Total needed from MIN to MAX
```

**After $200 profit:**
```
To MID: $300.00 remaining         ← $500 - $200
To MAX (2%): $1,000.00 remaining   ← Doesn't change (reference from MID)
Total to MAX: $1,300.00 remaining   ← $1,500 - $200
```

**After another $400 profit (total $600):**
- **Accumulated**: $600
- **Level Up**: Reached MID (need $500, have $600)
- **New Display at MID:**
```
To MID: -                         ← Now at MID
To MAX (2%): $400.00 remaining     ← $1,000 - $600 (remaining accumulated profit)
Total to MAX: $400.00 remaining
```

**Scenario 1C: Multi-Level Jump from MIN**
- **Starting**: MIN level, need $1,500 total to reach MAX
- **Trade Result**: +$2,000 profit
- **Result**: Jump directly from MIN (0.5%) → MAX (2%)
- **Surplus**: $500 excess profit
- **Final Display:**
```
To MID: -
To MAX (2%): -
Total to MAX: $0.00
```

---

#### **Example Set 2: Conservative Parameters (MAX=1%, MIN=0.25%)**

**Account: $100,000 | MAX: 1% | MID: 0.5% | MIN: 0.25%**

**Fixed Targets:**
- MIN → MID: Need $250 (0.5% × $100,000 × 0.5)
- MID → MAX: Need $500 (1% × $100,000 × 0.5)

**Scenario 2A: Loss at MAX (1%) → Drop to MID (0.5%)**
- **Loss Amount**: $1,000 (1% risk trade)
- **New Equity**: $99,000
- **Current Level**: 0.5% (MID)

**Display at MID:**
```
To MID: -                         ← Already at MID
To MAX (1%): $500.00 remaining   ← Amount needed from MID to MAX
Total to MAX: $500.00 remaining   ← Same since we're at MID
```

**Scenario 2B: Another Loss → Drop to MIN (0.25%)**
- **Loss Amount**: $500 (0.5% risk trade)
- **New Equity**: $98,500
- **Current Level**: 0.25% (MIN)

**Display at MIN:**
```
To MID: $250.00 remaining         ← Need $250 to reach MID
To MAX (1%): $500.00 remaining   ← Amount needed from MID to MAX (fixed)
Total to MAX: $750.00 remaining   ← Total needed from MIN to MAX
```

**After $150 profit:**
```
To MID: $100.00 remaining         ← $250 - $150
To MAX (1%): $500.00 remaining   ← Doesn't change
Total to MAX: $600.00 remaining   ← $750 - $150
```

---

#### **Example Set 3: Aggressive Parameters (MAX=3%, MIN=1%)**

**Account: $100,000 | MAX: 3% | MID: 1.5% | MIN: 1%**

**Fixed Targets:**
- MIN → MID: Need $750 (1.5% × $100,000 × 0.5)
- MID → MAX: Need $1,500 (3% × $100,000 × 0.5)

**Scenario 3A: Loss at MAX (3%) → Drop to MID (1.5%)**
- **Loss Amount**: $3,000 (3% risk trade)
- **New Equity**: $97,000
- **Current Level**: 1.5% (MID)

**Display at MID:**
```
To MID: -                         ← Already at MID
To MAX (3%): $1,500.00 remaining   ← Amount needed from MID to MAX
Total to MAX: $1,500.00 remaining
```

**Scenario 3B: Another Loss → Drop to MIN (1%)**
- **Loss Amount**: $1,500 (1.5% risk trade)
- **New Equity**: $95,500
- **Current Level**: 1% (MIN)

**Display at MIN:**
```
To MID: $750.00 remaining         ← Need $750 to reach MID
To MAX (3%): $1,500.00 remaining   ← Amount needed from MID to MAX
Total to MAX: $2,250.00 remaining   ← Total needed from MIN to MAX
```

---

### **SUMMARY OF KEY PRINCIPLES**

#### **1. Level-Based System**
- Always exactly 3 levels: MIN → MID → MAX
- MID is always 50% of MAX
- Fixed targets based on risk percentages

#### **2. Stage-Based Display Logic**
- **"To MID"**: Shows amount needed to reach MID from current position
- **"To MAX"**: Shows amount needed to reach MAX FROM MID position (fixed reference)
- **"Total to MAX"**: Shows total amount needed FROM CURRENT position to reach MAX

#### **3. Accumulation Rules**
- **Profits Add Up**: Multiple wins accumulate toward targets
- **Losses Reset**: Any loss resets accumulated profit to $0
- **Multi-Level Jumps**: Single trade can jump multiple levels if profitable enough
- **Continue Through Levels**: No reset when reaching intermediate levels

#### **4. Target Calculations**
```
MIN → MID: Need (MID% × AccountEquity) × 0.5
MID → MAX: Need (MAX% × AccountEquity) × 0.5
```

#### **5. Display Rules by Current Level**

**When at MIN:**
```
To MID: [Amount needed to reach MID]
To MAX: [Amount needed from MID to MAX]
Total to MAX: [Sum of both amounts]
```

**When at MID:**
```
To MID: -
To MAX: [Amount needed from MID to MAX]
Total to MAX: [Same as To MAX]
```

**When at MAX:**
```
To MID: -
To MAX: -
Total to MAX: $0.00
```

### **Critical Accumulation Logic**

#### **When Accumulated Profit RESETS:**
1. **Any Loss**: Reset to $0, start new recovery journey
2. **Reach MAX Level**: Reset to $0 (no recovery needed at maximum)

#### **When Accumulated Profit CONTINUES:**
- **Level Progression**: Keep accumulating profit through intermediate levels
- **Multi-Level Jumps**: Single trade can jump multiple levels
- **No Reset at Intermediate Levels**: Profit continues toward final MAX target

#### **Accumulation Algorithm:**
```cpp
IF profit > 0:
    accumulated_profit += profit

    IF accumulated_profit >= target_to_next_level:
        level_up()  // NO RESET of accumulated_profit

    IF current_level == MAX:
        accumulated_profit = 0  // Only reset at MAX

IF profit < 0:
    accumulated_profit = 0  // Reset on any loss
```

---

## 📈 **Profit Accumulation Rules**

### **When Profits Accumulate:**
- **Multiple Wins Add Up**: $300 + $400 = $700 total toward recovery
- **Continue Through Levels**: No reset when reaching intermediate levels
- **Multi-Level Jumps**: Single trade can jump multiple levels if profitable enough

### **When Accumulated Profit Resets:**
1. **Any Loss**: Reset to $0, start new recovery journey
2. **Reach MAX Level**: Reset to $0 (no recovery needed at maximum)

### **Recovery Progression Examples:**

**Example 1: Stage-by-Stage Recovery**
```
Start: 0.5% level, equity $99,000, accumulated $0
Trade 1: +$300 → accumulated $300 (need $200 more for 1%, $1,200 more for MAX)
Trade 2: +$300 → accumulated $600 (reach 1% level, continue accumulating)
Trade 3: +$900 → accumulated $1,500 (reach MAX level, reset to $0)
```

**Example 2: Multi-Level Jump**
```
Start: 0.5% level, equity $99,000, accumulated $0
Trade 1: +$2,500 → accumulated $2,500 (exceeds $1,500 needed for MAX)
Result: Jump directly from 0.5% to 2% (MAX) with $500 excess profit
```

---

## 🔄 **Transaction Processing Logic**

### **Trade Analysis Rules:**
1. **Process Only New Trades**: Skip already processed trades
2. **Symbol Specific**: Only process trades on current chart symbol
3. **Closed Trades Only**: Process only DEAL_ENTRY_OUT transactions
4. **Sequence Integrity**: Process in reverse chronological order

### **Trade Processing Workflow:**
```cpp
For each new closed trade:
    if(profit < 0):
        // Loss detected
        Reduce risk level (MAX→MID→MIN)
        Reset accumulated profit to $0
        Set new recovery starting point (current equity)
        Calculate new recovery targets
        Log transaction

    else if(profit > 0):
        // Profit detected
        Add profit to accumulated total
        Check for level progression
        Log transaction
```

### **Level Progression Check:**
```cpp
if(accumulatedProfit >= targetToNextLevel && currentRiskPercent < maxRiskPercent):
    Level up one or more levels
    Continue same accumulated profit (NO RESET)

if(currentRiskPercent == maxRiskPercent):
    accumulatedProfit = 0  // Reset only at MAX
```

---

## 📱 **Display Requirements**

### **Always Visible Information:**
```
Current Risk Level: [MIN/MID/MAX] (X.X%)
Drawdown: $XXX (X.X%)
Consecutive Losses: #X
Current Equity: $XXX,XXX.XX
```

### **LEVEL-BASED RECOVERY DISPLAY**

**The display is completely level-based and shows the exact amounts needed for each level:**

#### **When at 0.5% Level:**
```
To 1%: $XXX.XX
To 2%: $XXX.XX
Total to MAX: $XXX.XX
```

**Example - Initial State (no accumulated profit):**
```
To 1%: $500.00
To 2%: $1,500.00
Total to MAX: $1,500.00
```

**Example - After $150 profit:**
```
To 1%: $350.00     ← $500 - $150
To 2%: $1,500.00   ← Doesn't change until we reach 1%
Total to MAX: $1,350.00  ← $1,500 - $150
```

#### **When at 1.0% Level:**
```
To 1%: -
To 2%: $XXX.XX
Total to MAX: $XXX.XX
```

**Example - Initial State:**
```
To 1%: -
To 2%: $1,000.00
Total to MAX: $1,000.00
```

**Example - After $300 profit:**
```
To 1%: -
To 2%: $700.00     ← $1,000 - $300
Total to MAX: $700.00  ← $1,000 - $300
```

#### **When at 2.0% Level (MAX):**
```
To 1%: -
To 2%: -
Total to MAX: $0.00
```

### **Display Logic Rules:**

1. **"To 1%"**: Shows remaining amount to reach 1% level
   - Only displays when current level is 0.5%
   - Shows "-" when current level is 1% or higher

2. **"To 2%"**: Shows remaining amount to reach 2% level (MAX)
   - Displays when current level is below 2%
   - Amount is based on the current level's target

3. **"Total to MAX"**: Shows total amount still needed to reach MAX level
   - Always reflects the cumulative total remaining
   - Reduces as accumulated profit increases

### **Display Update Rules:**

- **Fixed Targets**: Recovery targets are fixed amounts based on risk levels
- **Progressive Reduction**: Amounts decrease as accumulated profit increases
- **Level Changes**: Display format changes when moving between levels
- **Reset Behavior**: All amounts reset to original targets when loss occurs

### **Display Precision:**
- All monetary values: 2 decimal places
- Percentages: 1 decimal place
- Use "$" prefix for all monetary values
- Use "-" to indicate no target needed

---

## 💾 **Persistent Storage System**

### **State Variables Storage:**
```csv
maxRiskPercent,midRiskPercent,currentRiskPercent,minRiskPercent,
peakEquity,startingEquity,currentLevelTarget,maxLevelTarget,
consecutiveLosses,levelStartTime,lastTradeType,
lastProcessedTicket,accountNumber,lastUpdateTime
```

### **Storage Rules:**
1. **File Location**: `RiskManager\` subdirectory
2. **Account Isolation**: Separate file per account/broker
3. **Automatic Migration**: Move from old locations to new structure
4. **Save Trigger**: Only when state variables change

### **Startup Recovery:**
1. Load state from persistent storage
2. Validate account number match
3. Continue from exact previous state
4. Update display with current information

---

## 🧮 **Mathematical Formulas**

### **Risk Level Calculations:**
```cpp
midRiskPercent = maxRiskPercent * 0.5;
```

### **LEVEL-BASED RECOVERY TARGET CALCULATIONS**

**Fixed Target Amounts (Based on Risk Percentages):**
```cpp
// For a $100,000 account with 0.5 recovery multiplier
target_0_5_to_1_0 = (1.0 * 100000 * 0.01) * 0.5;  // = $500
target_1_0_to_2_0 = (2.0 * 100000 * 0.01) * 0.5;  // = $1,000
```

**General Formula:**
```cpp
targetAmount = (targetRiskPercent * startingEquity) * 0.5;
```

**Important**: Targets are **FIXED** based on the equity when the recovery journey starts, not current equity.

### **Display Calculations Based on Current Level:**

**When at 0.5% level:**
```cpp
toLevel1 = max(0, target_0_5_to_1_0 - accumulatedProfit);
toLevel2 = max(0, (target_0_5_to_1_0 + target_1_0_to_2_0) - accumulatedProfit);
totalToMax = toLevel2;
```

**When at 1.0% level:**
```cpp
toLevel1 = 0;  // Already reached this level
toLevel2 = max(0, target_1_0_to_2_0 - accumulatedProfit);
totalToMax = toLevel2;
```

**When at 2.0% level (MAX):**
```cpp
toLevel1 = 0;
toLevel2 = 0;
totalToMax = 0;
```

### **Progress Calculations:**
```cpp
// Progress percentage toward next level
progressPercent = (accumulatedProfit / targetToNextLevel) * 100;

// Remaining amounts for display
remainingToNextLevel = max(0, targetToNextLevel - accumulatedProfit);
remainingToMax = max(0, totalTargetToMax - accumulatedProfit);
```

### **Accumulation Logic:**
```cpp
IF profit > 0:
    accumulatedProfit += profit;

    // Check for level progression (no reset on level up)
    IF accumulatedProfit >= targetToNextLevel AND currentLevel < MAX:
        currentLevel = nextLevel;
        // Keep accumulatedProfit, don't reset

    IF currentLevel == MAX:
        accumulatedProfit = 0;  // Only reset at MAX

IF profit < 0:
    accumulatedProfit = 0;  // Reset on any loss
    currentLevel = previousLevel;  // Drop down one level
```

### **Drawdown Calculations:**
```cpp
currentDrawdown = peakEquity - currentEquity;
drawdownPercent = (currentDrawdown / peakEquity) * 100;
```

---

## 📋 **Transaction Logging**

### **Required Data Points:**
```csv
Date,Time,RiskLevel,Equity,Profit,TradeType,
NextLevel,NextLevelTarget,MaxLevelTarget,StartingEquity
```

### **Special Transaction Types:**
- **INIT**: System initialization
- **LOSS**: Losing trade
- **PROFIT**: Winning trade
- **LEVEL_UP**: Recovery level achievement

### **Logging Rules:**
1. **Every Trade**: Log all closed trades
2. **Level Changes**: Log all risk level changes
3. **Initialization**: Log system startup
4. **File Organization**: Dedicated `RiskManager\` subdirectory

---

## 🎛️ **User Controls**

### **Risk Management Settings:**
- `inpMaxRiskPercent`: Maximum risk percentage (default 2.0)
- `inpMinRiskPercent`: Minimum risk percentage (default 0.5)
- `inpRecoveryThreshold`: Recovery multiplier (fixed at 0.5)
- `inpAutoDetectTrades`: Enable/disable automatic trade detection

### **Chart Control Settings:**
- `inpRunOnAllCharts`: Run on multiple charts (default false)
- `inpPreferredSymbol`: Restrict to specific symbol (optional)

### **Display Settings:**
- `inpLabelX/Y`: Panel positioning coordinates
- `inpShowCompactDisplay`: Compact vs detailed format
- `inpFontSize`: Text size adjustment
- Color customization options

---

## 🔧 **Multi-Chart Management**

### **Default Behavior (Recommended):**
- **Single Chart Mode**: Run indicator on only one chart
- `inpRunOnAllCharts = false`: Prevents multiple instances

### **Alternative Modes:**
1. **Symbol-Specific**: Run only on specified symbols
2. **All Charts**: Run on every chart (resource intensive)

### **Chart Filtering Logic:**
```cpp
bool ShouldRunOnChart() {
    if(inpRunOnAllCharts) return true;
    if(inpPreferredSymbol != "" && currentSymbol == inpPreferredSymbol) return true;
    return false;  // Default single chart mode
}
```

---

## ⚡ **Performance Optimization**

### **State Modification Tracking:**
- Save state only when variables actually change
- Prevent unnecessary file operations
- Efficient memory usage

### **Trade Processing Efficiency:**
- Process only new trades (avoid reprocessing)
- Skip non-closing deals
- Minimize history scanning

### **File Operation Optimization:**
- Create directories automatically
- Efficient CSV serialization
- Fast state loading/saving

---

## 🔍 **Debugging and Monitoring**

### **Comprehensive Recovery Analysis:**
For every trade, system provides:
```
🔍 === COMPREHENSIVE RECOVERY ANALYSIS ===
🔍 Current Level: MIN (0.50%)
🔍 This Transaction: PROFIT $50.00
🔍 Original Peak Equity: $100,000.00
🔍 Current Equity: $99,720.00
🔍 Total Drawdown: $280.00
🔍 Journey Started When: [timestamp]

🔍 Recovery Journey:
   Started from: $99,500.00
   Target for next level: $1,000.00
   Progress so far: $220.00
   Still needed: $780.00

✅ This WIN counts toward recovery!
   Recovery progress: 22.0%
🔍 =================================
```

---

## 📏 **Success Criteria**

### **Functional Requirements:**
1. **Immediate Risk Reduction**: Losses trigger immediate level down
2. **Accurate Recovery Tracking**: Profits accumulate correctly
3. **Multi-Level Jumps**: Large profits skip intermediate levels
4. **Reset Logic**: Only reset on losses or MAX achievement
5. **Persistent State**: Survive indicator restarts/system reboots
6. **Accurate Display**: Real-time progress information

### **Performance Requirements:**
1. **Fast Processing**: Minimal CPU/memory usage
2. **Reliable Operation**: No crashes or data corruption
3. **Efficient File I/O**: Quick state loading/saving
4. **Clean Compilation**: MQL5 Market compatible

### **User Experience Requirements:**
1. **Clear Information**: Always know current status and targets
2. **Intuitive Operation**: Easy to understand recovery progress
3. **Professional Display**: Clean, organized interface
4. **Reliable Behavior**: Consistent operation across conditions

---

## 🚫 **Modification Protocol**

### **Code Changes:**
This document represents the core system logic. Any modifications require:
1. **User Approval**: Explicit permission for changes
2. **Document Update**: This manual must reflect new logic
3. **Version Control**: Track all logic modifications
4. **Testing**: Verify changes don't break existing functionality

### **Change Types Requiring Approval:**
- Risk level progression logic
- Recovery target calculations
- State management rules
- Transaction processing workflow
- Display information requirements

---

## 📚 **Implementation Reference**

### **Primary Logic Sources:**
1. **This Document**: Complete system logic manual
2. **User Requirements**: Real trading scenarios and feedback
3. **Test Results**: Behavior verification with actual trades
4. **Performance Metrics**: System optimization feedback

### **Decision Hierarchy:**
1. **System Logic Manual** (this document) - Primary authority
2. **User Requirements** - Business logic validation
3. **Technical Constraints** - Implementation boundaries
4. **Performance Requirements** - Optimization targets

---

**Document Status**: AUTHORITY - Read Only
**Last Updated**: 2025-11-14
**Next Review**: As needed based on user feedback
**Access Level**: Core System Logic - User Permission Required for Modifications

# DragonHealth Wireframes v0.1

Below is a screen-by-screen wireframe specification for DragonHealth v0.1, written so you can paste it directly into Apple Notes and use it as the authoritative UX reference.

This is not visual fluff — it is interaction-precise, buildable, and optimized for speed of use.

---

## Assumptions & Scope

- iPhone-first (portrait)
- Single user
- iOS system components where possible
- One-hand use prioritized
- Logging speed > aesthetics

---

## DragonHealth – Wireframes v0.1

---

### 0. Global UI Principles

- Bottom Tab Bar (5 tabs)
- Large tap targets
- No modal overload
- Edit-in-place
- Color reflects target state, not emotion

Color semantics (global):

- Grey = not logged
- Blue = in progress
- Green = on target
- Amber = under target
- Red = over target (rule-aware)

---

### 1. Tab Bar (Persistent)

[ Today ] [ History ] [ Body ] [ Library ] [ Settings ]

---

### 2. TODAY (Primary Screen)

**Purpose**

Fast logging + instant feedback.

**Layout**

```
────────────────────────
TODAY · Tue 12 Mar

[ DAILY SUMMARY ]
────────────────────────
Drinks      ▓▓▓▓░ 1.2 / ≥1.5 L
Veg         ▓▓░░░ 2.5 / ≥3
Fruit       ▓▓▓░░ 2.0 / ≥2 ✔
Starchy     ▓▓░░░ 2.0 / 3
Protein     ▓▓▓▓░ 0.75 / 1
Treats      ▓▓▓░░ 0.75 / ≤1
Sports      ▓░░░░ 15 / ≥30 min

────────────────────────
[ MEALS ]
────────────────────────
▸ Breakfast        08:12
▸ Morning Snack    —
▸ Lunch            12:45
▸ Afternoon Snack  —
▸ Dinner           19:10
▸ Late Night       —
▸ Midnight         —
```

**Interactions**

- Tap category -> jump to day detail (History -> Day View)
- Tap meal -> Meal Detail
- Swipe left/right -> previous/next day
- Long-press day -> quick copy yesterday

---

### 3. MEAL DETAIL (Logging Surface)

**Purpose**

Ultra-fast portion entry.

**Layout**

```
────────────────────────
Dinner · 19:10

[ CATEGORY LIST ]
────────────────────────
Protein
[-] [¼] [+]     0.75

Starchy
[-] [¼] [+]     1.00

Veg
[-] [¼] [+]     1.50

Treats
[-] [¼] [+]     0.25

Sports
[-] [5m] [+]    0

────────────────────────
[ + Add from Library ]
```

**Interaction Rules**

- Tap + adds 1/4
- Long-press + accelerates
- +1 / +1/2 / +1/4 chips appear on long-press
- Values update live in Today summary
- No save button (auto-persist)

---

### 4. HISTORY (Adherence & Trends)

**Default View: Calendar Heatmap**

```
MAR 2026
Mo Tu We Th Fr Sa Su
⬜ 🟩 🟩 🟨 🟩 🟥 ⬜
🟩 🟩 🟩 🟩 🟨 🟩 ⬜
```

Legend:

- 🟩 = on target
- 🟨 = under (>= 1 category)
- 🟥 = over (>= 1 category)
- ⬜ = no data

Tap a Day -> DAY DETAIL

```
Tue 12 Mar

Protein     0.75 / 1     -0.25
Veg         2.5 / >=3     -0.5
Treats      0.75 / <=1    OK
Sports      15 / >=30     -15

[ Meals Breakdown ]
Breakfast ...
Lunch ...
Dinner ...
```

---

**Alternate View: Trends**

[ Week | Month | 6M | 1Y ]

Adherence %
███████░░ 78%

Protein hit rate     ▓▓▓▓▓░ 83%
Veg hit rate         ▓▓▓░░░ 62%
Treats compliance    ▓▓▓▓▓▓ 92%

---

### 5. BODY (Metrics & Trends)

**Layout**

```
────────────────────────
BODY · Today

Weight (kg)
[ 81.4 ]

Muscle %
[ 34.2 ]

Body Fat %
[ 19.8 ]

Waist (cm)
[ 88 ]

[ Save ]
```

Trends View (below inputs)

[ Week | Month | 6M | 1Y ]

Weight
──── raw
━━━ 7-day avg
```

**Rules**

- Input once/day
- Rolling average default ON
- Raw toggleable

---

### 6. LIBRARY (Food Portions)

**Purpose**

Consistency + education (not mandatory).

**Layout**

```
Search...

⭐ Chicken Breast
⭐ Oats
Apple
Greek Yoghurt
Salmon
```

**Food Detail**

```
Chicken Breast

Category: Protein
Default:
200 g -> 1.0 portion

Presets:
150 g -> 0.75
250 g -> 1.25

[ Add to Meal ]
```

---

### 7. SETTINGS

**Sections**

A. Plan

- Daily Targets
- Per-Meal Targets
- Target Rules

B. Categories

- [ Edit Categories ]
- + Add Category

Each category:

- Name
- Color
- Unit type
- Rule type
- Enable/disable

C. Meals

- Reorder Meals
- Enable/Disable
- Rename

D. Day Rules

- Day Cutoff Time   [ 04:00 ]
- Banking           [ ON ]

E. Data

- iCloud Sync       [ ON ]
- Export PDF

---

### 8. PDF EXPORT FLOW

Export ->
Select Range ->

- [ Last 7 Days ]
- [ Last 30 Days ]
- [ Custom ]

-> Generate PDF

PDF includes:

- Adherence summary
- Category stats
- Streaks
- Body metric charts

---

### 9. Error & Edge UX (Minimal)

- Over-logging shows red but never blocks
- Missing data is neutral (grey)
- No nagging alerts in v0.1

---

### 10. MVP Completion Checklist

- Can log full day in <60 seconds
- Can see "how am I doing today?" in 1 glance
- Can see trends without interpretation effort
- Can export and leave the app anytime

# DragonHealth iOS App - Specification v0.3 (Implemented Build)

## 1. Purpose

DragonHealth is a single-user, standalone iOS application designed to support weight loss through portion-based nutrition tracking, sports activity logging, and body metric trend analysis.

The app intentionally avoids calorie counting and focuses on:

- portion consistency
- daily adherence
- long-term behavioral trends
- simplicity and speed of use

## 2. Core Principles

- Portion-based tracking (not calories)
- Daily totals determine adherence
- Fast logging via Quick Add
- Clear over/under target visibility
- Configurable categories and targets
- On-device first, private by default

## 3. Data Model (Implemented)

### Categories

Each category has:

- name
- unit name
- enabled flag
- target rule
- sort order

### Units

Each unit has:

- name
- symbol
- allows decimal flag
- enabled flag
- sort order

### Meal Slots

Each meal slot has:

- name
- sort order

### Daily Logs

Each entry includes:

- date (normalized to the day boundary)
- meal slot
- category
- portion value
- optional amount value (original input)
- optional amount unit
- optional notes

### Body Metrics

Tracked per day:

- weight (kg)
- lean mass (kg)
- body fat (percent)
- waist circumference (cm)
- steps (count)

### Food Library Items

Each food item includes:

- name
- category mapping
- portion equivalent
- amount per portion (optional)
- amount unit (optional)
- optional notes
- favorite flag
- optional photo

### Care Team Meetings

Each meeting includes:

- date
- provider type (doctor or nutrition specialist)
- notes

### Health Documents

Each document includes:

- title
- file name
- file type (PDF or image)
- created date

### App Settings

- day cutoff time (minutes from midnight)
- profile image
- height (cm)
- target weight (kg)
- target weight date (date)
- motivation text
- doctor name
- nutrition specialist name

## 4. Meal Structure and Day Boundary

### Default Meal Slots (user-editable)

1. Breakfast
2. Morning Snack
3. Lunch
4. Afternoon Snack
5. Dinner
6. Late Night
7. Midnight

Notes:

- Meal slots are fully configurable in Manage > Plan & Meals.
- Day boundary is configurable (default 04:00). Entries before the cutoff time count toward the previous day.
- Meal timing windows are configurable in Manage > Plan & Meals. The global "+" uses the current time to pick the default meal slot.
- Each meal slot can be excluded from auto selection (e.g., "Brunch" on weekends).

## 5. Categories and Targets

### Default Categories

1. Unsweetened Drinks (L)
2. Vegetables (portions)
3. Fruit (portions)
4. Starchy Sides (portions)
5. Protein Sources (portions)
6. Dairy (portions)
7. Oils / Fats / Nuts (portions)
8. Treats (portions)
9. Sports (min)

Users can add, remove, rename, reorder, or disable categories.

### Target Rule Types

- Exact
- At least
- At most
- Range

Exact targets allow +/- 0.1 tolerance.

### Default Daily Targets (editable)

- Unsweetened Drinks: 1.0 to 2.0 L
- Vegetables: at least 3.0 portions
- Fruit: at least 2.0 portions
- Starchy Sides: exactly 3.0 portions
- Protein Sources: exactly 1.0 portion
- Dairy: exactly 3.0 portions
- Oils/Fats/Nuts: 2.0 to 3.0 portions
- Treats: at most 1.0 portion
- Sports: at least 30 minutes

## 6. Portion System

- Core portion values are rounded to 0.1 increments.
- Quick Add uses 0.1 increments (0.0 to 6.0).
- Food library portions use 0.1 increments.
- Amount inputs sync with portion values and round to 0.1.

## 7. Adherence Logic

- Daily totals are summed by category.
- Only enabled categories are evaluated.
- A day is on target if all enabled categories meet their target rule.

## 7A. Daily Score (Weighted + Intelligent) [Proposed]

Goal: Replace the binary green/red adherence with a 0-100 daily score that is
weighted, directionally smart (over/under penalties differ), and supports
simple compensation rules (e.g., extra sports can offset treats).

### 7A.1 Score Overview

- Daily score is a weighted average of per-category scores (0-100).
- Each category uses a "preference curve" to score deviations.
- Directional penalties let "over" and "under" behave differently.
- Optional compensation rules can reduce specific penalties.
- Score colors:
  - Green: 85-100
  - Yellow: 70-84
  - Red: < 70

### 7A.2 Category Score Model (Simple, Configurable)

Each category gets a `ScoreProfile` (defaults provided; user-tunable later).

```
ScoreProfile
- weight: Double (sum of enabled categories = 1.0)
- underPenaltyPerUnit: Double
- overPenaltyPerUnit: Double
- underSoftLimit: Double (units below preferred range where score reaches 50)
- overSoftLimit: Double (units above preferred range where score reaches 50)
- curve: linear | quadratic (quadratic feels "smarter" for larger deviations)
- capOverAtTarget: Bool (true = no penalty above target)
```

Preferred range is derived from `TargetRule`:
- exact(x): [x - 0.1, x + 0.1]
- atLeast(x): [x, +inf)
- atMost(x): (-inf, x]
- range(min, max): [min, max]

Scoring (per category):

```
if total within preferred range -> score = 100
else if under:
  deviation = preferredMin - total
  score = 100 - penalty(underPenaltyPerUnit, underSoftLimit, curve, deviation)
else if over:
  deviation = total - preferredMax
  if capOverAtTarget -> score = 100
  else score = 100 - penalty(overPenaltyPerUnit, overSoftLimit, curve, deviation)

score = clamp(score, 0, 100)
```

Penalty helper (simple + stable):

```
if curve == linear:
  penalty = 50 * (deviation / softLimit) * penaltyPerUnit
else (quadratic):
  penalty = 50 * (deviation / softLimit)^2 * penaltyPerUnit
```

Notes:
- `softLimit` is the deviation where score hits ~50 (before multipliers).
- `penaltyPerUnit` lets categories be more/less strict.
- `capOverAtTarget` supports "over is fine" behaviors.

### 7A.3 Compensation Rules (Optional, Minimal)

Compensation is deliberately limited to avoid complexity. Rule type:

```
CompensationRule
- fromCategoryID (penalized category)
- toCategoryID (compensating category)
- ratio (units of "to" needed per 1 unit of "from" overage)
- maxOffset (max overage that can be offset)
```

Example (Treats offset by Sports):
- ratio = 15 minutes of sports per 1 treat portion over target
- maxOffset = 2.0 treat portions

Algorithm:
1. Compute overage for `fromCategory`.
2. Compute surplus for `toCategory` (above its target).
3. Offset = min(overage, surplus / ratio, maxOffset).
4. Reduce the `fromCategory` overage by the offset before scoring.

### 7A.4 Default Profiles (Initial Proposal)

Weights (sum = 1.0):
- Unsweetened Drinks: 0.10
- Vegetables: 0.12
- Fruit: 0.08
- Starchy Sides (Carbs): 0.12
- Protein Sources: 0.12
- Dairy: 0.08
- Oils / Fats / Nuts: 0.06
- Treats: 0.12
- Sports: 0.20

Directional preferences:
- Unsweetened Drinks: under = penalize, over = neutral (`capOverAtTarget = true`)
- Vegetables/Fruit: under penalize, over mild (cap optional)
- Starchy Sides (Carbs): over penalize more than under
- Protein Sources: under penalize more than over
- Dairy: symmetric
- Oils/Fats/Nuts: mild penalties both sides
- Treats: strong over penalty, under neutral
- Sports: under penalize, over neutral

### 7A.5 Output

- Daily score (0-100) shown in Today header.
- Category rows show per-category score (small) and color.
- History screen shows score instead of binary adherence, with optional trendline.

### 7A.6 Storage and Implementation (Concrete, Minimal)

Add lightweight, optional scoring config without changing target rules:

```
Category
- scoreProfile: ScoreProfile? (optional, defaults from a lookup table)
```

If `scoreProfile` is nil, a default profile is inferred from `TargetRule` and
category name (matching built-in defaults).

Core additions:
- `DailyScoreEvaluator` (parallel to `DailyTotalEvaluator`)
- `CategoryScore` (categoryID + score + total + adjustedTotal)
- `DailyScoreSummary` (categoryScores + overallScore + color)

UI:
- Today header shows overall score + color.
- Category tiles show score in small font and optional tooltip.
- History list shows score badge per day.

Migration:
- No breaking changes required if `scoreProfile` is optional.
- Future: allow editing weights + penalty sliders in Manage > Plan & Meals.

## 8. Screens (Implemented)

### Today

- Daily header with adherence summary.
- Category overview tiles with progress status.
- Tapping a category row opens a per-category day detail screen listing all items logged for that category on the selected day.
- Per-category day detail screen supports swipe actions:
  - swipe to delete an item
  - swipe the opposite direction to edit an item
- Per-category day detail screen includes a "+" action to Quick Add a new item for that category on the same day (category is prefilled).
- Per-meal summaries with scroll-to-meal support.
- Composite foods show as a single row in meal summaries with an expand/collapse affordance to reveal component entries.
- Component entries in category detail lists show an indicator that they came from a composite (e.g., label or badge with composite name).
- Display settings for category and meal summary styles.
- Quick Add flow: meal slot + category + portion or amount (when available) + optional notes.
- Food library picker to prefill category and portion.
- Food library picker uses a compact library list (reduced row padding/insets, smaller thumbnails) to show more items per screen.
- If a category is already selected in Quick Add, the food library picker defaults its filter to that category (user can change).
- Entry edit and delete flows with notes.

#### Revised Today + Quick Add Flow (Category-First)

```mermaid
flowchart TD
    A[Today] --> B[Category Tiles Canvas]
    A --> C[Meals Summary (secondary)]
    A --> D[Global + Add Entry]

    B --> E[Category Day Detail]
    E --> F[Quick Add (category prefilled)]
    E --> G[Edit Entry]
    E --> H[Delete Entry]

    D --> I[Quick Add (category-first)]
    I --> J{Category selected?}
    J -->|No| K[Pick Category]
    J -->|Yes| L[Pick Meal Slot (optional)]
    K --> L
    L --> M[Enter Portion or Amount + Unit]
    M --> N[Optional Notes]
    N --> O[Save Entry]
    O --> E

    C --> P[Meal Detail (secondary view)]
    P --> Q[Add Entry in Meal (category required)]
    Q --> I
```

Notes:
- Category-first is the primary mental model: Today centers on category tiles and category detail.
- Quick Add always requires category selection; meal slot is optional but defaults to the current meal slot.
- The current meal slot is determined by the meal timing windows (time of day), skipping any meals marked "exclude from auto".
- Over-target visibility only applies when targets are range-based or at-most; for minimum targets, exceeding is not negative.

#### Today GUI Wireframe

```
----------------------------------------------------------------
Today
----------------------------------------------------------------
SUN - 1 Feb 26                                     On target: 6/9
Adherence summary: 3 categories missing target

[ Category Tiles Canvas ]
----------------------------------------------------------------
Vegetables                          Target 3.0 portions
Logged 1.5 portions
MISSING
1.5 PORTIONS (red)

Fruit                               Target 2.0 portions
Logged 0.0 portions
MISSING
2.0 PORTIONS (red)

Unsweetened Drinks                  Target 2.0 L
Logged 0.8 L
MISSING
1.2 L (red)

Sports                              Target 30 min
Logged 0 min
MISSING
30 MIN (red)
----------------------------------------------------------------
```

Notes:
- Date format is fixed to `SUN - 1 Feb 26` (weekday abbrev, dash, day, month abbrev, 2-digit year).
- Each category tile displays the missing units to target in a large, high-contrast font.
- Show the "MISSING" label and missing value only when the category is below target.
- When the target is met, do not show a missing label/value (avoid "Missing" + "0 portions").
- Missing values use a red font (example: `1 portion` in red).

#### Per-Category Day Detail (Wireframe)

```
-------------------------------------------
< Back                Vegetables        [+]
-------------------------------------------
Tue, Jan 31 (Today)

• 0.5 portions  Breakfast    (swipe ← edit | swipe → delete)
• 1.0 portions  Lunch        (swipe ← edit | swipe → delete)
• 0.1 portions  Snack        (swipe ← edit | swipe → delete)

-------------------------------------------
Notes:
- "+" opens Quick Add with day + category prefilled
- Empty state shows “No items yet” with a centered "+" CTA
- Items that originated from a composite show a small indicator (e.g., “from Hamburger”) and can deep-link to the composite detail sheet.
```

### History

- Graphical date picker.
- Day-level adherence summary.
- Per-meal entry lists with edit and delete (composite foods appear as a grouped row with expandable components).
- Per-category totals and target status.
- Quick Add for historical days.

### Body Metrics

- 7-day rolling averages for weight, lean mass, body fat, waist, and steps.
- Metric history charts (iOS 16+ Charts).
- Time frame selector for body metric charts: 1 week, 1 month, 3 months, 6 months, all.
- One selected time frame applies to all body metric charts (single shared setting).
- List of logged metric entries.
- Add metrics sheet with date and values.
- Apple Health sync status and manual sync control.
- Body GUI canvases:
  - Current Weight canvas: "Last weight", "Last week", "Last month" labels left-aligned; their values right-aligned.
  - Target Weight canvas: show target weight and target weight date.
  - Target Progress canvas (below Target Weight):
    - target weight + target weight date
    - difference between current weight and target weight
    - days remaining to the target weight date (today -> target date)
    - weekly reduction required between now and the target date (difference / remaining weeks)

#### Body GUI Wireframe (Current + Target)

```
----------------------------------------------------------------
Body
----------------------------------------------------------------

[ Current Weight ]  (canvas)
---------------------------------------------------------------
Current Weight                                  84.2 kg
Last weight                                     84.6 kg
Last week                                      -0.8 kg
Last month                                     -2.1 kg
---------------------------------------------------------------

[ Target Weight ]  (canvas)
---------------------------------------------------------------
Target Weight                                   78.0 kg
Target Date                               Jun 15, 2026
---------------------------------------------------------------

[ Target Progress ]  (canvas)
---------------------------------------------------------------
Target Weight                                   78.0 kg
Target Date                               Jun 15, 2026
Difference                                     -6.2 kg
Days remaining                                  134 days
Weekly reduction required                       -0.32 kg
---------------------------------------------------------------
```

### Library

- List of foods with favorites section.
- Add/edit food sheets with category, portion equivalent, amount per portion + unit (optional), notes, and favorite flag.
- Optional food photos (choose from photo library or search Unsplash).
- Unsplash photos store attribution metadata (photographer + source link).
- Food library items can prefill Quick Add.
- Composite foods / recipes:
  - Composite items are built from multiple existing foods with per-serving quantities.
  - Logging a composite expands into atomic entries for each component (totals and scoring stay category-based).
  - Composite items can have their own photo; this photo is used in library and meal lists.
  - Component foods can still have their own photos (optional).

### Documents

- Import PDFs and images into a local documents library.
- QuickLook preview for stored documents.
- Delete documents with file cleanup.

### Manage

- Profile and care team:
  - Profile details: photo, height, target weight, target weight date, current weight, motivation text.
  - Care team details: doctor and nutrition specialist names.
  - Care team meeting log with notes.
- Plan and meals:
  - Day cutoff time selector.
  - Categories list with add/edit/delete and target rule editing.
  - Meal slots list with add/edit/delete.
  - Units list with add/edit/disable.
- Data and backup:
  - iCloud backup status, last backup metadata, and manual backup trigger (optional note).
  - Restore backup with compatibility checks and confirmation.
- Integrations:
  - Apple Health sync status and manual sync trigger.
- Documents:
  - Document library entry point.

### Restore Backup

- iCloud backup list with compatibility checks.
- Restore action with confirmation dialog.

## 9. Storage and Backup

- On-device SQLite database stored in the app documents directory.
- iCloud backups are optional and run daily when iCloud is available.
- Manual backups are available in Manage > Data and Backup with optional notes.
- Restore is available from Manage > Data and Backup and only allows compatible database versions.
- Documents and images are stored locally in app documents subfolders.
- No accounts, no external servers.

## 10. Apple Health Sync

- Read-only sync from Apple Health for weight, body fat, lean mass, waist, steps, and active energy (Move kcal).
- Manual sync is available in Manage > Integrations and Body Metrics.
- Automatic sync runs on launch if permission is granted.

## 11. Privacy

- All data stays on-device unless the user enables iCloud backups.
- Apple Health access is optional and read-only.
- Food photo search calls the Unsplash API and downloads the chosen image to local storage.
- No analytics, tracking, or third-party data sharing beyond photo search.

## 12. Explicitly Out of Scope (Current Build)

- iCloud sync across devices (backup only)
- PDF export
- Apple Health write-back
- Notifications and reminders
- Widgets / lock screen quick add
- Meal photos per log entry
- Streak analytics
- Adherence heatmaps or trend charts

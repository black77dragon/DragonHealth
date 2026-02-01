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
- Display settings for category and meal summary styles.
- Quick Add flow: meal slot + category + portion or amount (when available) + optional notes.
- Food library picker to prefill category and portion.
- Entry edit and delete flows with notes.

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
```

### History

- Graphical date picker.
- Day-level adherence summary.
- Per-meal entry lists with edit and delete.
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

### Library

- List of foods with favorites section.
- Add/edit food sheets with category, portion equivalent, amount per portion + unit (optional), notes, and favorite flag.
- Optional food photos.
- Food library items can prefill Quick Add.

### Documents

- Import PDFs and images into a local documents library.
- QuickLook preview for stored documents.
- Delete documents with file cleanup.

### Manage

- Profile and care team:
  - Profile details: photo, height, target weight, current weight, motivation text.
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

- Read-only sync from Apple Health for weight, body fat, lean mass, waist, and steps.
- Manual sync is available in Manage > Integrations and Body Metrics.
- Automatic sync runs on launch if permission is granted.

## 11. Privacy

- All data stays on-device unless the user enables iCloud backups.
- Apple Health access is optional and read-only.
- No analytics, tracking, or third-party data sharing.

## 12. Explicitly Out of Scope (Current Build)

- iCloud sync across devices (backup only)
- PDF export
- Apple Health write-back
- Notifications and reminders
- Widgets / lock screen quick add
- Meal photos per log entry
- Composite foods / recipes
- Streak analytics
- Adherence heatmaps or trend charts

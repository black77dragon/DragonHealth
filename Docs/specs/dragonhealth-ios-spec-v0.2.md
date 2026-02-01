# DragonHealth iOS App - Specification v0.2 (Implemented Build)

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

### Body Metrics

Tracked per day:

- weight (kg)
- muscle mass (percent)
- body fat (percent)
- waist circumference (cm)

### Food Library Items

Each food item includes:

- name
- category mapping
- portion equivalent
- optional notes
- favorite flag

### App Settings

- day cutoff time (minutes from midnight)

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

- Meal slots are fully configurable in Settings.
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

Exact targets allow +/- 0.25 tolerance.

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

- Core portion values are rounded to 0.25 increments.
- Quick Add uses 0.5 increments (0.0 to 6.0).
- Food library portions use 0.25 increments.

## 7. Adherence Logic

- Daily totals are summed by category.
- Only enabled categories are evaluated.
- A day is on target if all enabled categories meet their target rule.

## 8. Screens (Implemented)

### Today

- Daily header with adherence summary.
- Category overview tiles with progress status.
- Per-meal summaries (cards or strips).
- Display settings for category and meal summary styles.
- Quick Add flow: meal slot + category + portion.

### History

- Graphical date picker.
- Day-level adherence summary.
- Per-category totals and target status.

### Body Metrics

- 7-day rolling averages.
- List of logged metric entries.
- Add metrics sheet with date and values.

### Library

- List of foods with favorites section.
- Add food sheet with category, portion equivalent, notes, and favorite flag.
- Delete items via swipe.
- Food library is not yet integrated into logging flow.

### Settings

- Day cutoff time selector.
- Categories list with add/edit/delete and target rule editing.
- Meal slots list with add/edit/delete.
- iCloud backup status and manual backup trigger.

## 9. Storage and Backup

- On-device SQLite database stored in the app documents directory.
- iCloud backups are optional and run daily when iCloud is available.
- Manual backups are available in Settings.
- No accounts, no external servers.

## 10. Privacy

- All data stays on-device unless the user enables iCloud backups.
- No analytics, tracking, or third-party data sharing.

## 11. Explicitly Out of Scope (Current Build)

- iCloud sync across devices (backup only)
- PDF export
- Apple Health integration
- Notifications and reminders
- Widgets / lock screen quick add
- Meal photos
- Composite foods / recipes
- Streak analytics
- History heatmaps or trend charts

# DragonHealth iOS App - Specification v0.1

## 1. Purpose

DragonHealth is a single-user, standalone iOS application designed to support weight loss through portion-based nutrition tracking, sports activity logging, and body metric trend analysis.

The app intentionally avoids calorie counting and focuses on:

- portion consistency
- daily adherence
- long-term behavioral trends
- simplicity and speed of use

## 2. Core Principles

- Portion-based tracking (not calories)
- Daily budget with banking across meals
- Fast logging (under 10 seconds per meal)
- Clear over/under target visibility
- Motivation via streaks and trends (not guilt)
- Fully configurable categories and targets
- On-device first, private by default

## 3. Meal Structure

### Default Meal Slots (user-editable)

1. Breakfast
2. Morning Snack
3. Lunch
4. Afternoon Snack
5. Dinner
6. Late Night
7. Midnight

Notes:

- Snacks are separate meals
- Late Night and Midnight entries count for the same day
- Day boundary defined by configurable cutoff time (default: 04:00)

## 4. Categories (Configurable)

Each category has:

- name
- icon and color
- unit type
- daily target rule
- enabled/disabled flag

### Default Categories

1. Unsweetened Drinks (liters)
2. Vegetables (portions)
3. Fruit (portions)
4. Starchy Sides (portions)
5. Protein Sources (portions)
6. Dairy (portions)
7. Oils / Fats / Nuts (portions)
8. Treats (Sweets / Salty / Alcohol) (portions)
9. Sports (minutes)

Users can add, remove, rename, reorder categories.

## 5. Portion System

### Portion Increments

- 1.0
- 0.5
- 0.25

### Portion Definition Modes

- Global default portions per category
- Food-specific portion mappings (library)
- Hybrid model supported

### Mixed Dishes

- Portions are split manually in v0.1

## 6. Targets and Rules

### Target Levels

- Daily targets (primary, bankable)
- Per-meal guidance targets (secondary)

### Target Rule Types

- Exact (e.g., Starchy = 3.0)
- At least (e.g., Vegetables >= 3.0)
- At most (e.g., Treats <= 1.0)
- Range (e.g., Fats 2.0-3.0)

### Default Daily Targets (editable)

- Unsweetened Drinks: >= 1-2 L
- Vegetables: >= 3 portions
- Fruit: >= 2 portions
- Starchy Sides: = 3 portions
- Dairy: = 3 portions
- Protein Sources: = 1 portion
- Oils/Fats/Nuts: 2-3 portions
- Treats: <= 1 portion
- Sports: >= 30 minutes

## 7. Banking Logic

- Portions can be shifted freely between meals
- Only daily totals determine success
- Meal targets act as guidance, not enforcement

## 8. Sports Tracking

### v0.1 Model

- Unit: minutes
- Daily target configurable (e.g., 30 min)
- Logged per meal or separately

Future option:

- Sports portions (e.g., 1 portion = 30 min moderate)

## 9. Body Metrics

Tracked daily:

- Weight (kg)
- Muscle mass (percent or kg)
- Body fat (percent)
- Waist circumference (cm)

Features:

- Raw values
- 7-day rolling average
- Weekly, monthly, 6-month, and 1-year views

## 10. Food Library

Each food item includes:

- Name
- Category mapping
- Portion equivalents (grams to portions)
- Optional notes
- Favorite flag

Used for:

- Faster logging
- Education
- Consistency

## 11. Streaks and Motivation

### Adherence Definition

A day is on target if all enabled categories meet their rule.

Tolerance:

- plus or minus 0.25 portions for exact targets

Metrics:

- Current streak
- Best streak
- Percent days on target (rolling windows)
- Category-level wins even if full day missed

No cheat days.

## 12. Main Screens

### Today

- Daily summary by category
- Remaining / over portions
- Meal cards with quick plus/minus logging
- Fast logging without navigation

### History

- Calendar heatmap (on target / off target)
- Category-level over/under detail
- Weekly, monthly, yearly summaries

### Body

- Metric input
- Trend charts with averages

### Library

- Food list
- Portion mappings
- Favorites

### Settings

- Categories
- Meal slots
- Targets
- Day cutoff time
- iCloud sync
- Export

## 13. Data and Sync

- On-device storage
- iCloud sync (opt-in)
- No accounts
- No external servers

## 14. Export

### PDF Export

- Date range selectable
- Includes:
  - Adherence summary
  - Streaks
  - Category stats
  - Body metric trends

## 15. Backlog (Explicit)

- Apple Health integration
- Meal photos
- Composite foods / recipes
- Widgets / lock screen quick add
- Notifications and reminders

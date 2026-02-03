# DragonHealth iOS - Voice Log Design Spec v0.1

## 1. Purpose

Add a voice-driven logging flow that converts speech into structured meal entries. The feature targets fast logging with a review step, using on-device Apple Speech recognition and a lightweight parser that maps to the existing food library, categories, and portion system.

## 2. Goals

- Capture speech and generate a live transcript (English US/UK, German if available).
- Parse the transcript into draft items (food, amount, unit, portion, meal slot).
- Present a review UI that allows corrections before saving.
- Save entries using existing `DailyLogEntry` and `AppStore.logPortion` flows.
- Keep data on-device; no health data compliance requirements.

## 3. Non-Goals (v0.1)

- Cloud speech transcription or LLM parsing.
- Background/continuous dictation.
- Multi-user profiles or collaboration.
- Automatic nutrition calculations.

## 4. User Flow

1. User taps **Voice Log** in Today.
2. A sheet opens with:
   - Language picker (EN-US, EN-GB, DE).
   - Mic button to start/stop recording.
   - Live transcript area.
3. User taps **Parse** to generate draft items.
4. Draft list shows editable rows (food, category, amount, unit, portion, meal slot).
5. User corrects any flagged issues.
6. User taps **Save**, entries are written to the daily log.

## 5. UI/UX Requirements

- Voice Log entry point placed alongside Quick Add in Today.
- Live transcript updates while recording.
- Draft rows highlight missing or low-confidence fields.
- Save disabled until all draft rows have required fields:
  - Meal slot
  - Category
  - Portion
- Provide explicit error messages for:
  - Speech permission denied
  - Speech unavailable for selected language
  - Empty transcript

## 6. Data & Domain Mapping

### 6.1 Draft Model

```
VoiceDraft
- transcript: String
- mealSlotID: UUID?
- items: [VoiceDraftItem]

VoiceDraftItem
- foodText: String
- matchedFoodID: UUID?
- categoryID: UUID?
- amountValue: Double?
- amountUnitID: UUID?
- portion: Double?
- notes: String?
- warnings: [VoiceDraftWarning]
```

### 6.2 Parsing Rules (v0.1)

- Detect meal slot keywords (EN/DE) from transcript.
- Extract items using regex patterns:
  - "<number> <unit> <food>"
  - "<number> <food>"
- Normalize number formats: `0,5` -> `0.5`.
- Normalize units:
  - l/L -> ml
  - kg -> g
  - piece/pieces/Stück -> pc
- Food matching:
  - exact or normalized match against `FoodItem.name`
  - fallback to fuzzy match (token overlap)
- Portion calculation:
  - if `FoodItem.amountPerPortion` available, compute portion
  - if not, set warning and require user input

## 7. Architecture

### 7.1 Services

- `SpeechCaptureService`
  - Uses `AVAudioEngine` + `SFSpeechRecognizer`
  - Exposes transcript, state, and errors

- `VoiceDraftParser`
  - Stateless parser that maps transcript -> `VoiceDraft`

### 7.2 Storage

- No new tables required.
- Use existing `DailyLogEntry` saving path in `AppStore`.

## 8. Permissions

Add Info.plist keys:
- `NSSpeechRecognitionUsageDescription`
- `NSMicrophoneUsageDescription`

## 9. Localization

- Speech locale codes:
  - English (US): `en-US`
  - English (UK): `en-GB`
  - German: `de-DE`
- Meal slot keyword mapping includes EN/DE synonyms.

## 10. Acceptance Criteria

- User can open Voice Log from Today.
- Speech transcript is captured on-device in selected language.
- Parsed draft list is shown with editable fields.
- Entries save into the daily log and appear in Today.
- Errors are shown for missing permissions or unsupported language.

## 11. Future Enhancements

- Optional cloud transcription fallback
- LLM-based parsing for better food/portion accuracy
- Synonym training from user corrections
- Add "Save as new Food Item" flow from draft

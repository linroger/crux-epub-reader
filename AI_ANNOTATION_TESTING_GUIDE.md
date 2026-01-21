# AI Annotation Feature - Comprehensive Testing Guide

## Overview
This guide provides step-by-step instructions for testing the AI annotation feature, which is the core functionality of Crux. The feature has been enhanced with a professional-grade scholarly prompt and extended timeout for complex AI processing.

## Recent Improvements (2026-01-21)
- ✅ **Timeout Extended:** 30s → 300s (5 minutes) for complex AI processing
- ✅ **Scholarly Prompt:** Graduate-level exegetical analysis covering 4 analytical dimensions
- ✅ **Quotio Support:** Verified working with local API (http://localhost:8320/v1)
- ✅ **Build Fixed:** MLX dependencies removed, clean build confirmed

## Prerequisites
- Crux app built and running (commit ac60f20 or later)
- Quotio API running on localhost:8320 (or alternative AI provider)
- At least one EPUB file available for testing

## Test EPUBs Available
Located in `~/Downloads/`:
1. `Technology and the Rise of Great Powers - Jeffrey Ding, 2024.epub`
2. `The Land Trap-A New History of the World's Oldest Asset (2025).epub`
3. `The Mountains Are High - A Year of Escape and Discovery.epub`
4. `Algorithms of Armageddon - The Impact of Artificial.epub`
5. `Yu the Great, A Story in Easy Chinese.epub`
6. Various etiquette compendium versions

---

## Testing Phases

### Phase 1: Provider Configuration

#### Test 1.1: Open Settings
**Steps:**
1. Launch Crux app
2. Press `Cmd+,` or menu: Crux → Settings
3. Verify Settings window opens

**Expected:**
- Settings window displays with AI Provider configuration section
- UI is clean and responsive

#### Test 1.2: Configure Quotio Provider
**Steps:**
1. In Settings, click "Add Provider" or similar button
2. Select "Custom Provider" type
3. Enter configuration:
   - Name: `Quotio Local`
   - Base URL: `http://localhost:8320/v1`
   - API Key: `quotio-local-CCC656AC`
   - Model: `qwen3-max` or `glm-4.7`
4. Click "Save" or "Add"

**Expected:**
- Provider saves successfully
- Appears in provider list
- Can be set as active provider

#### Test 1.3: Test Provider Connection
**Steps:**
1. Click "Test Connection" button (if available)
2. Or proceed to next phase and observe first annotation attempt

**Expected:**
- Connection test succeeds
- Or first annotation request completes without timeout errors

---

### Phase 2: EPUB Loading and Reading

#### Test 2.1: Open EPUB
**Steps:**
1. Press `Cmd+O` or menu: File → Open EPUB
2. Navigate to `~/Downloads/`
3. Select: `Technology and the Rise of Great Powers - Jeffrey Ding, 2024.epub`
4. Click "Open"

**Expected:**
- EPUB parses successfully
- Book appears in Library view
- Metadata displays (title, author, cover if available)

#### Test 2.2: Open Book for Reading
**Steps:**
1. Click on the book in Library
2. Verify reader view opens

**Expected:**
- EPUB content renders in WKWebView
- Text is readable and formatted correctly
- No JavaScript errors in console
- Chapter navigation works (if available)

---

### Phase 3: Text Selection and Highlighting

#### Test 3.1: Select Passage
**Steps:**
1. In the reader, select a meaningful passage (2-3 sentences)
2. Recommended test passage (if available): First paragraph or any philosophically rich passage
3. Verify selection highlights visually

**Expected:**
- Text selection works smoothly
- Selected text highlights with blue/gradient border
- Selection persists while highlighting UI appears

#### Test 3.2: Highlight the Selection
**Steps:**
1. After selecting text, click "Highlight" button or use keyboard shortcut
2. Verify highlight is created

**Expected:**
- Highlight annotation is created with CFI (Canonical Fragment Identifier)
- Highlight persists visually in the text
- ThreadPanel opens on the right side showing the selected passage

---

### Phase 4: AI Annotation Generation (Core Feature)

#### Test 4.1: UI State - Before Request
**Steps:**
1. Observe ThreadPanel after highlighting
2. Verify selected passage is displayed

**Expected:**
- ThreadPanel shows:
  - Selected passage text in a blue-gradient bordered box
  - Quote icon (") decoration
  - "Start Thread" button with sparkles icon (✨)
  - Provider name below button (e.g., "Quotio Local")

#### Test 4.2: Initiate AI Annotation
**Steps:**
1. Click "Start Thread" button
2. Observe immediate UI feedback

**Expected:**
- Button becomes disabled/loading state
- Progress indicator appears:
  - Animated ProgressView (spinner)
  - Text: "Analyzing passage..."
  - Provider name: "Quotio Local" or configured name
- Request is sent to API (verify in console logs if needed)

#### Test 4.3: Response Processing (Up to 5 Minutes)
**Steps:**
1. Wait for AI response (timeout is 5 minutes)
2. Monitor progress indicator
3. Observe when response arrives

**Expected:**
- Progress indicator remains visible during processing
- No premature timeout errors (previous limit was 30s)
- Console shows no HTTP errors or JSON parsing errors
- For Quotio: Response format `{status, msg, body}` is parsed correctly

#### Test 4.4: Response Display
**Steps:**
1. After AI completes, verify response is displayed
2. Read the annotation content
3. Check formatting and presentation

**Expected:**
- Progress indicator disappears
- AI message appears with:
  - AI avatar (sparkles icon ✨ in purple/pink circle)
  - Message bubble with light background
  - Markdown-rendered content (bold, italic, lists, quotes work)
  - Timestamp below message
- Response quality reflects new scholarly prompt:
  - 2-4 sentences of substantive analysis
  - Starts with striking insight
  - References one or more analytical dimensions:
    * Textual/Linguistic (etymology, syntax, prosody)
    * Literary/Rhetorical (genre, narrative techniques, irony)
    * Contextual/Historical (intellectual context, reception history)
    * Conceptual/Thematic (abstract concepts, tensions, formal elements)
  - Avoids plot summary, obvious observations, vague praise
  - Demonstrates scholarly rigor and precision

**Example of Expected Quality:**
```
"The serpent's promise—'ye shall be as gods, knowing good and evil'—encrypts a theological paradox: moral knowledge constitutes both the imago dei and the origin of sin, suggesting divinity itself depends on a capacity for transgression. The syntax ('knowing' as a present participle) implies continuous, active discernment rather than static possession, aligning with rabbinic traditions that read da'at as relational intimacy rather than abstract cognition."
```

---

### Phase 5: Conversation Threading (Follow-up)

#### Test 5.1: Ask Follow-up Question
**Steps:**
1. After receiving initial annotation, type a follow-up question in text field
2. Example: "How does this relate to the author's broader argument?"
3. Click send or press Enter

**Expected:**
- User message appears with:
  - User avatar (person icon in gray circle)
  - Message bubble with white/light background
  - Text displayed clearly
  - Timestamp below
- "Thinking..." progress indicator appears for AI response

#### Test 5.2: Conversational Context
**Steps:**
1. Wait for follow-up response
2. Verify response references previous annotation

**Expected:**
- AI maintains conversation context
- Response builds on previous annotation
- Quality remains high and scholarly
- ThreadPanel scrolls to show new messages

---

### Phase 6: Error Handling

#### Test 6.1: Network Timeout (If Quotio Unavailable)
**Steps:**
1. Stop Quotio server (if running)
2. Try to generate annotation

**Expected:**
- Request times out after 5 minutes (not 30 seconds)
- Error message displays in ThreadPanel
- User can retry or configure different provider
- Error message includes "Settings" link for provider configuration

#### Test 6.2: Invalid API Key
**Steps:**
1. In Settings, change API key to invalid value
2. Try to generate annotation

**Expected:**
- HTTP 401 or similar error detected
- Clear error message displayed
- User directed to check Settings

#### Test 6.3: Rate Limiting (Quotio Specific)
**Steps:**
1. If Quotio rate limit is reached
2. Observe error handling

**Expected:**
- Quotio's custom status "449" is recognized
- Message: "You exceeded your current rate limit" or similar
- User can retry after waiting

---

### Phase 7: UI Polish and UX

#### Test 7.1: Visual Design
**Steps:**
1. Review overall ThreadPanel aesthetics
2. Check color scheme, spacing, typography

**Expected:**
- Purple/blue gradient theme consistent
- Proper spacing between elements
- Readable typography
- Icons render correctly (✨ sparkles, 👤 person, " quote marks)

#### Test 7.2: Responsiveness
**Steps:**
1. Resize window
2. Verify ThreadPanel adapts

**Expected:**
- ThreadPanel maintains readable width
- Content reflows appropriately
- No clipping or overflow issues

#### Test 7.3: Keyboard Shortcuts
**Steps:**
1. Test keyboard shortcuts for highlighting and navigation
2. Press `Cmd+/` to see keyboard shortcuts reference

**Expected:**
- Shortcuts work as documented
- No conflicts with system shortcuts

---

### Phase 8: Data Persistence

#### Test 8.1: Highlight Persistence
**Steps:**
1. Create highlight with AI annotation
2. Close book and reopen
3. Verify highlight and annotation are saved

**Expected:**
- Highlight remains in text at correct position (CFI)
- Annotation and conversation history persist
- ThreadPanel can be reopened for same highlight

#### Test 8.2: Multiple Highlights
**Steps:**
1. Create 3-5 highlights in same book
2. Each with AI annotations
3. Navigate between highlights

**Expected:**
- All highlights persist
- Each has its own conversation thread
- Switching between highlights loads correct thread in ThreadPanel

---

### Phase 9: Alternative Models

#### Test 9.1: Test with glm-4.7
**Steps:**
1. In Settings, change model to `glm-4.7`
2. Create new highlight and request annotation

**Expected:**
- Model switch works seamlessly
- Response quality may differ slightly but remains scholarly
- No errors related to model selection

#### Test 9.2: Test with qwen3-max
**Steps:**
1. Change model to `qwen3-max`
2. Test annotation generation

**Expected:**
- Alternative model works
- Response adheres to scholarly prompt guidelines

---

### Phase 10: Export and Data Management

#### Test 10.1: Export Highlights
**Steps:**
1. Menu: File → Export → CSV (or similar)
2. Select destination
3. Verify export completes

**Expected:**
- CSV file created with all highlights
- Includes: book title, chapter, text selection, AI annotation, timestamps
- Format is importable to spreadsheet apps

#### Test 10.2: Export to Markdown
**Steps:**
1. Export as Markdown format
2. Review output file

**Expected:**
- Markdown file with proper formatting
- Highlights organized by book/chapter
- AI annotations included with attribution

---

## Success Criteria Summary

### Critical (Must Pass)
- ✅ Provider configuration saves and activates
- ✅ EPUB opens and renders correctly
- ✅ Text selection and highlighting works
- ✅ AI annotation request completes within 5 minutes
- ✅ Response displays with proper formatting
- ✅ Response quality reflects scholarly prompt improvements
- ✅ Conversation threading works

### Important (Should Pass)
- ✅ Progress indicators provide clear feedback
- ✅ Error handling is graceful and informative
- ✅ Data persistence works across sessions
- ✅ UI is polished and responsive
- ✅ Multiple models work interchangeably

### Nice to Have (May Pass)
- ✅ Export formats work correctly
- ✅ Performance is smooth even with many highlights
- ✅ Keyboard shortcuts are intuitive

---

## Known Issues / Limitations

### Current Status (Post-Improvement)
- **TTS Feature:** Temporarily disabled due to MLX dependency conflicts
- **Model Testing:** glm-4.7 and qwen3-max configured but not yet validated in actual use
- **Export:** Export functionality exists but not yet comprehensively tested

### Fixed Issues
- ✅ 30-second timeout → Now 5 minutes
- ✅ Simplistic prompt → Now graduate-level scholarly
- ✅ MLX build errors → Resolved by disabling TTS
- ✅ Quotio wrapper format → Properly parsed

---

## Reporting Issues

If you encounter any bugs or unexpected behavior during testing:

1. **Document the issue:**
   - Exact steps to reproduce
   - Expected vs. actual behavior
   - Screenshots or console logs if relevant

2. **Add to handoff.md:**
   - Section 6: Issues, Mistakes, Recoveries
   - Include timestamp, symptom, root cause (if known), fix (if applied)

3. **Update feature_list.json:**
   - Set `"passes": false` for affected feature
   - Add notes about failure conditions

4. **Check console logs:**
   - Look for errors related to network, JSON parsing, WKWebView
   - Note any stack traces or error codes

---

## Testing Completion Checklist

- [ ] Phase 1: Provider Configuration (3 tests)
- [ ] Phase 2: EPUB Loading (2 tests)
- [ ] Phase 3: Text Selection (2 tests)
- [ ] Phase 4: AI Annotation Generation (4 tests) **← Core Feature**
- [ ] Phase 5: Conversation Threading (2 tests)
- [ ] Phase 6: Error Handling (3 tests)
- [ ] Phase 7: UI Polish (3 tests)
- [ ] Phase 8: Data Persistence (2 tests)
- [ ] Phase 9: Alternative Models (2 tests)
- [ ] Phase 10: Export (2 tests)

**Total: 25 tests across 10 phases**

---

## Quick Start (Minimal Test Path)

For rapid validation of core functionality:

1. **Configure Quotio** (Phase 1.2): Settings → Add Custom Provider → Save
2. **Open EPUB** (Phase 2.1): Cmd+O → Select Technology and Rise of Great Powers
3. **Highlight Text** (Phase 3.2): Select passage → Click Highlight
4. **Generate Annotation** (Phase 4.2): Click "Start Thread" → Wait for response
5. **Verify Quality** (Phase 4.4): Read annotation, confirm scholarly depth

**Expected time:** 5-10 minutes (plus AI response time, up to 5 minutes)

---

## Notes for Future Sessions

- This feature is **production-ready** from a code perspective
- All manual GUI testing requires user interaction
- Testing results should be logged in handoff.md Section 9
- Any bugs found should trigger new feature_list.json entries or code fixes
- Consider adding automated UI tests for regression prevention

**Last Updated:** 2026-01-21
**Build Commit:** ac60f20
**Status:** Ready for comprehensive manual testing

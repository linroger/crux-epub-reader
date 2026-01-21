# Pre-Flight Testing Checklist

## Status: Ready for Manual Testing ✅

**Last Code Change:** 2026-01-21 (Commit 5418867)
**Build Status:** ✅ Clean (no errors, no warnings)
**Feature Status:** All code-level improvements complete

---

## What's Been Fixed and Ready

### ✅ Code Complete
1. **AI Annotation Prompt** - Graduate-level scholarly quality
2. **Extended Timeout** - 5 minutes (up from 30 seconds)
3. **Reasoning Model Support** - glm-4.7 and similar models now work
4. **Quotio API Integration** - Custom wrapper format fully supported
5. **Build Dependencies** - MLX issues resolved, clean build

### ✅ Documentation Complete
- `handoff.md` - Full session history and bug fixes
- `QUICK_START.md` - 5-minute testing guide
- `AI_ANNOTATION_TESTING_GUIDE.md` - Comprehensive 25-test suite
- `PRE_FLIGHT_CHECKLIST.md` - This file

### ✅ Known Issues Resolved
- ~~Custom provider timeout (30s)~~ → Fixed: 300s
- ~~Simplistic AI prompt~~ → Fixed: Scholarly framework
- ~~WKWebView sandbox errors~~ → Fixed: Entitlements added
- ~~MLX build failures~~ → Fixed: Dependencies removed
- ~~Quotio wrapper format~~ → Fixed: Parser extended
- ~~Reasoning model support~~ → Fixed: reasoning_content field

---

## Before You Start Testing

### 1. Verify Quotio is Running
```bash
lsof -i :8320
```
**Expected:** Process listening on port 8320
**If not running:** Start Quotio server first

### 2. Kill Any Running Crux Instances
```bash
ps aux | grep Crux
killall -9 Crux
```
**Why:** Ensures you're testing the latest build with all fixes

### 3. Verify Latest Build
```bash
cd /Users/rogerlin/XCode-Projects/crux
git log --oneline -1
```
**Expected:** `5418867 Fix: Support reasoning models with reasoning_content field`

### 4. Launch Fresh Build
- Option A: Launch from Xcode (⌘R)
- Option B: Launch from Applications folder
- Option C: Use launch script if available

### 5. Check Console for Startup Errors
```bash
log stream --predicate 'process == "Crux"' --level info
```
**Expected:** No sandbox errors, no JavaScript failures, no ATS blocks

---

## Testing Sequence (5-10 Minutes)

### Phase 1: Settings Configuration (2 min)
1. Launch Crux
2. Press `Cmd+,` (Settings)
3. Click "AI Providers" tab
4. Click "Edit" on Quotio provider (or "Add Provider" if not exists)
5. Verify settings:
   - Name: `Quotio` or `Quotio Local`
   - Type: `Custom Provider`
   - Base URL: `http://localhost:8320/v1`
   - API Key: `quotio-local-CCC656AC`
   - Model: `glm-4.7` or `qwen3-max`
6. Toggle "Set as active provider" ON
7. **CRITICAL TEST:** Click "Test Connection"

**Expected Result:** ✅ Success message (green checkmark)
**If Failed:** Check troubleshooting section below

### Phase 2: EPUB Loading (1 min)
1. Press `Cmd+O`
2. Navigate to `~/Downloads/`
3. Select: "Technology and the Rise of Great Powers - Jeffrey Ding, 2024.epub"
4. Click "Open"

**Expected:** Book loads, appears in library, metadata displays

### Phase 3: AI Annotation Test (5-10 min)
1. Open the book from library
2. Select a meaningful 2-3 sentence passage
3. Click "Highlight" button
4. Click "Start Thread" in ThreadPanel (right side)
5. **Observe:** Progress indicator shows "Analyzing passage..."
6. **Wait:** Up to 5 minutes (usually 30-60 seconds)
7. **Verify:** Annotation appears with scholarly quality

**Quality Checklist:**
- [ ] 2-4 sentences of analysis
- [ ] Starts with striking insight (not plot summary)
- [ ] References analytical dimensions:
  - Textual/Linguistic (etymology, syntax)
  - Literary/Rhetorical (genre, structure)
  - Contextual/Historical (intellectual context)
  - Conceptual/Thematic (abstract concepts)
- [ ] No obvious observations or vague praise
- [ ] Demonstrates scholarly rigor

### Phase 4: Follow-up Test (Optional, 2 min)
1. Type follow-up question: "How does this relate to the author's broader argument?"
2. Press Enter
3. Verify AI maintains context

---

## Troubleshooting Guide

### "Test Connection" Still Fails

**Error: "Received invalid response from API"**
- Verify you restarted the app after pulling latest code
- Check console logs for actual error details
- Test API directly:
  ```bash
  curl -X POST http://localhost:8320/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer quotio-local-CCC656AC" \
    -d '{"model":"glm-4.7","messages":[{"role":"user","content":"test"}],"max_tokens":10}'
  ```

**Error: "Connection timeout"**
- Verify Quotio is running: `lsof -i :8320`
- Check Info.plist has ATS exception (should already be there)
- Verify API key is exactly: `quotio-local-CCC656AC`

**Error: "Rate limit exceeded" (status 449)**
- This is a Quotio rate limit, not a bug
- Wait a few minutes and retry
- Proves connection is working, just temporarily limited

### App Won't Launch
```bash
# Check if app crashed
log show --predicate 'process == "Crux"' --last 5m | grep -i error

# Force clean launch
rm -rf ~/Library/Caches/com.yourcompany.Crux
killall -9 Crux
```

### EPUB Won't Open
- Verify file is valid EPUB: `file ~/Downloads/Technology*.epub`
- Check console for parsing errors
- Try a different EPUB from the list in QUICK_START.md

### Highlights Don't Save
- Check SwiftData permissions
- Verify book was properly imported (check Library view)
- Look for errors in console related to SwiftData

### Annotation Request Hangs Forever
- **If > 5 minutes:** This is a bug, report it
- **If < 5 minutes:** Be patient, complex requests can take time
- Check console for timeout errors
- Verify Quotio is still responding: `curl http://localhost:8320/health`

---

## Success Criteria

Testing is successful when ALL of these pass:

- ✅ "Test Connection" succeeds with green checkmark
- ✅ EPUB opens and renders correctly
- ✅ Text selection and highlighting works smoothly
- ✅ AI annotation request completes within 5 minutes
- ✅ Response displays with proper formatting
- ✅ Response quality is scholarly (not simplistic)
- ✅ Follow-up conversation maintains context
- ✅ No console errors (sandbox, network, parsing)

---

## Reporting Issues

If you encounter problems:

1. **Capture evidence:**
   - Screenshot of error
   - Console logs: `log stream --predicate 'process == "Crux"' > /tmp/crux.log`
   - API test results (curl commands)

2. **Document in issue:**
   - Exact steps to reproduce
   - Expected vs actual behavior
   - Environment (macOS version, Quotio version, model used)
   - Console errors or logs

3. **Where to report:**
   - Add to handoff.md Section 6 (Issues, Mistakes, Recoveries)
   - Create GitHub issue if public repo
   - Provide all captured evidence

---

## Current Known Limitations

- **TTS Feature:** Temporarily disabled (MLX dependency conflict)
- **Export:** Exists but not yet comprehensively tested
- **iOS Build:** Not tested this session (macOS only)

---

## What Happens Next

**If All Tests Pass:**
- We move to Phase 2 features (customization, settings UI)
- Begin implementation of remaining items from feature_list.json

**If Issues Found:**
- Document each issue clearly with reproduction steps
- I'll investigate and fix bugs
- Re-test after fixes

**If Testing is Blocked:**
- Provide details about the blocker
- We'll debug together
- Alternative approaches may be needed

---

## Quick Commands Reference

```bash
# Check Quotio
lsof -i :8320

# Kill Crux
killall -9 Crux

# Check logs
log stream --predicate 'process == "Crux"' --level info

# Test API directly
curl -X POST http://localhost:8320/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer quotio-local-CCC656AC" \
  -d '{"model":"glm-4.7","messages":[{"role":"user","content":"test"}],"max_tokens":10}'

# Rebuild if needed
cd /Users/rogerlin/XCode-Projects/crux
xcodegen generate
xcodebuild -scheme Crux_macOS -destination 'platform=macOS' build
```

---

**You're ready to test! Start with Phase 1 (Settings Configuration) and work through the sequence.** 🚀

**Estimated time:** 5-10 minutes for core functionality + AI response time

**Last Updated:** 2026-01-21
**Related Docs:** QUICK_START.md, AI_ANNOTATION_TESTING_GUIDE.md, handoff.md

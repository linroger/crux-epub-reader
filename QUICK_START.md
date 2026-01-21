# Crux AI Annotation - Quick Start Guide

## 🚀 Get Testing in 5 Minutes

### Step 1: Configure AI Provider (2 minutes)
1. Launch Crux app
2. Press `Cmd+,` (Settings)
3. Click "AI Providers" tab
4. Click "Add Provider" button
5. Fill in:
   - **Name:** `Quotio Local`
   - **Type:** `Custom Provider`
   - **API Key:** `quotio-local-CCC656AC`
   - **Base URL:** `http://localhost:8320/v1`
   - **Model:** `qwen3-max` or `glm-4.7`
6. Toggle "Set as active provider"
7. Click "Test Connection" (optional)
8. Click "Save"

### Step 2: Open an EPUB (1 minute)
1. Press `Cmd+O`
2. Navigate to `~/Downloads/`
3. Select: **"Technology and the Rise of Great Powers - Jeffrey Ding, 2024.epub"**
   - (Or any other EPUB from the list)
4. Click "Open"

### Step 3: Test AI Annotation (2 minutes + AI response time)
1. In the reader, **select a meaningful passage** (2-3 sentences)
   - Look for philosophically rich or technically complex text
2. Click **"Highlight"** button
3. Click **"Start Thread"** button in ThreadPanel (right side)
4. **Observe progress indicator:**
   - Spinner with "Analyzing passage..."
   - Provider name displayed
5. **Wait for response** (up to 5 minutes)
6. **Verify response quality:**
   - 2-4 sentences of scholarly analysis
   - References analytical dimensions:
     - Textual/Linguistic (etymology, syntax)
     - Literary/Rhetorical (genre, intertextuality)
     - Contextual/Historical (intellectual context)
     - Conceptual/Thematic (abstract concepts)
   - No plot summary or obvious observations
   - Demonstrates scholarly rigor

### Step 4: Test Follow-up Conversation (Optional)
1. Type a follow-up question in the text field
2. Example: *"How does this relate to the author's broader argument?"*
3. Press Enter
4. Verify AI maintains conversation context

---

## ✅ Success Criteria

**The feature works if:**
- ✅ Progress indicator shows during processing
- ✅ Response arrives within 5 minutes (no timeout)
- ✅ Response is scholarly and substantive (not simplistic)
- ✅ Markdown formatting renders correctly
- ✅ Follow-up conversation maintains context
- ✅ No network errors or parsing failures

---

## 📚 Available Test EPUBs

Located in `~/Downloads/`:

**Recommended for testing:**
1. **Technology and the Rise of Great Powers** - Jeffrey Ding, 2024
   - Good for tech/policy analysis
2. **The Land Trap: A New History** - Mike Bird, 2025
   - Historical/economic content
3. **Algorithms of Armageddon** - George Galdorisi
   - AI/military technology (great for technical annotation)

**Alternative options:**
4. The Mountains Are High - Travel narrative
5. Yu the Great - Chinese language/culture
6. Etiquette Compendium - Social history

---

## 🛠️ Troubleshooting

### "No AI provider configured"
- Verify you clicked "Save" after configuring provider
- Check that "Set as active provider" toggle was ON
- Restart app and check Settings → AI Providers

### Connection timeout / Network error
- Verify Quotio is running: `lsof -i :8320`
- Check API key is exactly: `quotio-local-CCC656AC`
- Verify Base URL is: `http://localhost:8320/v1` (no trailing slash)

### "Invalid response from API"
- Check Quotio logs for errors
- Try "Test Connection" in Settings
- Verify model is supported (`qwen3-max`, `glm-4.7`)

### Request takes too long
- This is normal - timeout is 5 minutes for complex processing
- Wait patiently for first response
- Subsequent responses may be faster (if Quotio caches)

---

## 📝 What to Test

### Core Functionality
- [ ] Provider configuration saves
- [ ] EPUB opens and renders
- [ ] Text selection works
- [ ] Highlight creates successfully
- [ ] AI request initiates
- [ ] Progress indicator displays
- [ ] Response arrives (no timeout)
- [ ] Response quality is scholarly
- [ ] Markdown renders correctly
- [ ] Follow-up conversation works

### Error Handling
- [ ] Graceful handling if Quotio unavailable
- [ ] Clear error messages
- [ ] Settings link works in error states

### UI Polish
- [ ] Smooth animations
- [ ] Proper spacing and typography
- [ ] Purple/blue gradient theme consistent
- [ ] Icons render correctly (✨ sparkles, 👤 person)

---

## 📖 Full Documentation

For comprehensive testing guide with 25 tests across 10 phases:
- See: **`AI_ANNOTATION_TESTING_GUIDE.md`**

For session continuity and technical details:
- See: **`handoff.md`**

For feature roadmap:
- See: **`feature_list.json`** and **`FEATURE_PLAN.md`**

---

## 🎯 What's Been Improved

**Recent enhancements (commit ac60f20):**

1. **Extended Timeout**
   - Was: 30 seconds
   - Now: 300 seconds (5 minutes)
   - Handles complex AI processing

2. **Professional Scholarly Prompt**
   - Was: Simplistic bullet points
   - Now: Graduate-level exegetical framework
   - Covers 4 analytical dimensions with concrete examples

3. **Quotio API Support**
   - Parses custom wrapper format: `{status, msg, body}`
   - Handles rate limiting (status "449")
   - Maintains OpenAI/Claude compatibility

4. **Build Fixed**
   - MLX audio dependencies removed
   - Clean build with no warnings
   - App launches without sandbox errors

---

## 🚦 Current Status

**✅ Code Complete** - All AI annotation improvements implemented and committed
**✅ Build Passing** - App compiles and launches successfully
**✅ Documentation Ready** - Comprehensive testing guide available
**⏳ Manual Testing** - Requires GUI interaction (next step)

**Last Updated:** 2026-01-21
**Commit:** ac60f20
**Time to Test:** ~10 minutes for core flow

---

## 💡 Tips for Best Results

1. **Select rich passages** - Philosophy, technical analysis, literary prose work best
2. **Provide context** - Select enough text for AI to understand (2-3 sentences minimum)
3. **Be patient** - First request may take full 5 minutes as model loads
4. **Try different models** - `qwen3-max` and `glm-4.7` may produce different styles
5. **Use follow-ups** - Ask "How does this relate to X?" or "What's the historical context?"

---

**Ready to test? Start with Step 1 above! ⬆️**

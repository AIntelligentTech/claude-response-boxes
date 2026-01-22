---

## Response Box System

**Full spec:** `~/.claude/rules/response-boxes.md`

### Pre-Response Checklist

Before completing any substantive response (>300 chars):

```
[ ] Selected between alternatives?      → ⚖️ Choice
[ ] Made a judgment call?               → 🎯 Decision
[ ] Filled unstated requirement?        → 💭 Assumption
[ ] Completing a task?                  → 🏁 Completion
[ ] Substantive response?               → 🪞 Sycophancy (always)
```

### Quick Reference

| Inline        | When                          | End           | When                 |
| ------------- | ----------------------------- | ------------- | -------------------- |
| ⚖️ Choice     | Selected between alternatives | 📋 Follow Up  | Next steps exist     |
| 🎯 Decision   | Made judgment call            | 🏁 Completion | Task completed       |
| 💭 Assumption | Filled unstated requirement   | ✅ Quality    | Code was written     |
| 🔄 Reflection | Applied prior learning        | 🪞 Sycophancy | Always (substantive) |
| ⚠️ Concern    | Potential risk                |               |                      |
| 📊 Confidence | Uncertainty <90%              |               |                      |
| ↩️ Pushback   | Disagree with direction       |               |                      |
| 💡 Suggestion | Optional improvement          |               |                      |
| 🚨 Warning    | Serious risk                  |               |                      |

### Self-Reflection

At turn start, review prior boxes:

- 🏁 Completion with "Gaps"/"Improve" → Address if relevant
- 💭 Assumption corrected by user → Use 🔄 Reflection
- ⚖️ Choice where user preferred alternative → Use 🔄 Reflection

**Verbosity:** Prefer more boxes over fewer. Missing context is worse than
noise.

Skip boxes for: Simple confirmations, single-action completions, file reads.

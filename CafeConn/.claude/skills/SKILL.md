---
name: fix-bugs
description: Use when fixing a specific bug in CafeConnect. Triggers on "баг", "bug", "сломано", "не работает", "fix", "починить".
---

# Bug Fix Workflow for CafeConnect

1. READ the full class/widget involved before touching anything.
2. Write a one-line hypothesis: "Bug X happens because Y."
3. Make the minimal change that fixes Y — do not refactor while fixing.
4. Verify with `flutter analyze` (must be 0 errors).
5. Report: file changed + line range + what changed + what to manually test.

## Known root causes to check first
- Navigation reset → GoRouter recreated inside Consumer builder (see CLAUDE.md)
- Font fallback → google_fonts runtime fetch failing offline (see CLAUDE.md)
- State not updating → notifyListeners() missing after mutation
- Dark theme unreadable → static AppColors not switching with theme

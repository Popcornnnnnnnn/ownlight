# Simulator UAT

Use this checklist for Private Moments iOS UI work, especially visual polish where screenshots matter.

## Default Device

- Prefer an iPhone 13 Pro simulator, matching the user's real device class.
- Reuse the named project simulator when present: `Private Moments iPhone 13 Pro`.
- If the simulator is missing, create or select an iPhone 13 Pro-class simulator instead of drifting to newer/larger phones.

## Run And Verify

1. Before starting, shut down old simulators and quit Simulator.app to free memory.
2. Run `npm run ios:simulator:demo` from the active worktree.
3. Verify the real rendered UI in Simulator, not only build output or static mockups.
4. Save review screenshots under `.tmp/ui-review/<slug>/` when judging visual changes.
5. During user UAT, leave Simulator open on the exact screen being reviewed.
6. After approval or completion, run `xcrun simctl shutdown all` and quit Simulator.app.

## Visibility Checks

- Do not trust `simctl launch` alone. Confirm the target device is booted, the app is installed/launched, and the Simulator window is visible/frontmost for the user.
- If the app is running but the user cannot see the window, activate/reopen Simulator, raise the window with accessibility scripting, and move/resize it into a visible area.
- If launch/install fails with `NSMachErrorDomain -308`, or `simctl install` hangs, manually boot the target simulator, open Simulator with the target device, terminate/uninstall/reinstall/launch the app, and kill stuck `simctl install` processes if needed.

Keep this file concise. Add only recurring simulator UAT problems and proven fixes.

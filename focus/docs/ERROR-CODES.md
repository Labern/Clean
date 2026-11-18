# Focus error codes

Every failure Focus can notice is recorded with a code, in `~/Library/Logs/Focus/errors.jsonl` (one JSON object per
line; past 1 MB it rolls to `errors.1.jsonl`). Each record has: `t` (time), `code`, `name`, `area`, `detail`, `v`
(Focus version), `run` (one id per launch), `macOS`, `ctx` (what was involved: bundle ids, OS status, error text) and
`trail` (the last 20 lines of `Focus.log` before it). The same code and detail inside 10 s is counted
(`repeatsBefore` on the next one) rather than written again. Nothing a person types, and no page contents, is ever
recorded.

The same line also goes into `~/Library/Logs/Focus.log` as `ERROR Fxxx name — detail`, among the ordinary events.

- **Summary:** `/Applications/Focus.app/Contents/MacOS/Focus --diagnose [DAYS]` (default 7): copies running,
  Accessibility, counts by code, and the last 15 in full.
- **Crashes:** a fatal signal writes `crash.txt` (signal and stack) in the moment, and the next launch turns it into
  F902. A launch that finds the last run's `running.json` still there records F903, with the newest macOS crash report
  for Focus if there is one.
- **Tests** never write to the real record: self-tests and renders log to a temporary folder (GUI check 37).

| Code | Name | Area | Means | Check |
|---|---|---|---|---|
| F101 | quitTimedOut | session | An app was asked to quit and was still open when the queue moved on (usually a "Save changes?" prompt). | It is on the waiting list in the menu; `ctx.id` says which. |
| F102 | quitRefused | session | macOS refused to send an app the quit request. | The app may be a system process or already quitting. |
| F110 | restoreAppMissing | session | An app parked in a session was no longer at its path when the session ended. | Moved, deleted or on an ejected drive; `ctx.path`. |
| F111 | restoreLaunchFailed | session | macOS returned an error reopening an app at the end of a session. | `ctx.error`. |
| F112 | modeAppNotFound | session | A mode lists an app that is not installed. | Edit the mode; `ctx.id`. |
| F201 | appNotFound | apps | An app asked for by bundle id is not installed. | `ctx.id`. |
| F202 | appOpenFailed | apps | macOS returned an error opening an app. | `ctx.error`. |
| F203 | forceQuitRefused | apps | A force quit was refused. | Usually a system process. |
| F301 | hotkeyTaken | shortcuts | macOS would not register a shortcut: another app holds it. | `ctx.id` (1 session, 2 menu, 3 window, 4 Super Smart Search, 100–109 modes), `ctx.status`. Change it in Settings ▸ Shortcuts. |
| F401 | scriptNotAllowed | search | The Mac has not allowed Focus to control that browser (Automation, −1743). | System Settings ▸ Privacy & Security ▸ Automation ▸ Focus. |
| F402 | scriptAppNotRunning | search | The browser quit between being seen and being asked (−600). | Harmless if rare. |
| F403 | scriptTimedOut | search | The browser did not answer in time. | A busy or hung browser; many tabs. |
| F404 | scriptFailed | search | Any other script error; the browser's own words are in `ctx.said`. | Read `ctx.said`. |
| F405 | scriptCouldNotStart | search | `osascript` itself would not start. | Very unusual: check the system. |
| F406 | pageReadingOff | search | The browser's "Allow JavaScript from Apple Events" is off, so page contents can't be read. | Chrome: View ▸ Developer ▸ Allow JavaScript from Apple Events. |
| F410 | tabNotFound | search | The chosen tab was not where it was, nor found by its address. | `ctx.answer`, `ctx.browser`; the tab may have closed. |
| F411 | notBroughtForward | search | The app was asked to come forward and did not; Focus opened it Dock-style instead. | `ctx.activate`, `ctx.front` (what was in front instead). |
| F501 | accessibilityMissing | permissions | Windows can't be read or raised: no Accessibility permission. Once per run. | Super Smart Search page ▸ Allow…, or System Settings ▸ Privacy & Security ▸ Accessibility. |
| F601 | settingsUnreadable | settings | Saved settings exist but could not be read; the defaults are used and nothing is overwritten. | `ctx.bytes`. |
| F701 | updateCheckFailed | network | The release page did not answer, or answered with an error. | Offline, or GitHub rate limits. |
| F702 | feedbackFailed | network | The feedback post failed; the email fallback opened instead, so nothing was lost. | `ctx.status`, `ctx.error`; check `/api/feedback`. |
| F703 | pricingFetchFailed | network | The live prices could not be read; the shipped or cached ones are used. | Offline, or `pricing.json` on the site. |
| F801 | chimeFailed | sound | A session sound would not play. | Output device; `--chime-check`. |
| F901 | uncaughtException | focus | An Objective-C exception reached the top. | `ctx.stack`. |
| F902 | crashed | focus | Focus stopped on a fatal signal; the stack is kept. | `ctx.stack`; also the macOS crash report. |
| F903 | endedUnexpectedly | focus | The last run never quit: a crash, a force quit or the Mac losing power. | `ctx.crashReport`, `ctx.lastVersion`. |
| F904 | staleCopyReplaced | focus | A running Focus did not answer within 2 s and was replaced. | `ctx.pids`; look for F903/F902 before it. |

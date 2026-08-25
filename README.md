# FlowKeys

[![CI](https://github.com/PG-1012/FlowKeys/actions/workflows/ci.yml/badge.svg)](https://github.com/PG-1012/FlowKeys/actions/workflows/ci.yml)

Copy several things. Paste the one you want.

FlowKeys keeps a history of what you copy and puts it behind the ⌘V you
already press — no new shortcut to learn, no window to go find.

```
⌘C  ⌘C  ⌘C          copy three things
⌘V                  pastes the newest — exactly like always
⌘V V V              hold ⌘, keep tapping V to walk back through history
                    release ⌘ to paste what's highlighted
```

The overlay appears next to your text cursor, so you never look away from
what you're writing.

---

## The one rule

**An ordinary paste stays ordinary.**

Tap ⌘V and let go and you get the most recent item, instantly, with no
overlay and no delay — indistinguishable from the system paste. The history
only shows up if you *keep holding ⌘*, the same way ⌘Tab only shows the app
switcher if you hold ⌘ down.

That constraint drove the whole design, and it's what the test suite mostly
checks.

| | |
|---|---|
| `⌘V` tap and release | Paste most recent |
| `⌘V` then `V`, `V`… | Step back through history, overlay appears |
| `⌘⇧V` while cycling | Step forward again |
| Hold `⌘V` and wait | Overlay appears without moving the selection |
| `1`–`9` while cycling | Jump straight to that entry |
| Type while cycling | Filter history as you type |
| `esc` | Cancel, paste nothing |

Type-to-filter is the one that changes how it feels once history gets long:
hold ⌘, tap V, then type `inv` to narrow fifty entries down to the invoice
number you copied ten minutes ago. Backspace widens it again.

---

## Install

Requires macOS 13+ and Xcode command line tools.

```bash
git clone https://github.com/PG-1012/FlowKeys.git
cd FlowKeys
make install        # builds and copies to /Applications
open /Applications/FlowKeys.app
```

Or `make run` to build and launch in place.

### Granting permission

FlowKeys needs **Accessibility** access, and will prompt on first launch:

> System Settings → Privacy & Security → Accessibility → enable FlowKeys

Then **quit and reopen FlowKeys**. macOS only hands an already-running
process a fresh event tap in some cases, so a relaunch is the reliable move.

If the menu still says it needs access after that, you probably have stale
duplicate entries from an earlier build:

```bash
make reset-permission     # clears them
```

This is not optional, and it's worth knowing why. Intercepting ⌘V means
*consuming* the keystroke before the frontmost app sees it, and macOS gates
that behind Accessibility. There is no lesser permission that would do.

---

## Troubleshooting

**⌘V pastes the same thing every time, and the list appears in the middle of
the screen.** You are running a different build — almost certainly a stale
Xcode one from `~/Library/Developer/Xcode/DerivedData`. macOS only stops two
copies of the *same* bundle identifier from running, so an old build under a
different identifier runs happily alongside the real one and wins the race
for ⌘V.

Open the menu bar item: it shows the running version and location at the
bottom, and warns with a **Quit the other FlowKeys** button if it finds
another build. If the location reads `⚠︎ Xcode build folder`, that is the
problem.

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/FlowKeys-*
make install && open /Applications/FlowKeys.app
```

**An app shows the list but nothing pastes** (Microsoft Word is the known
case). Some apps track modifier state from `flagsChanged` events rather than
reading each event's flags. FlowKeys posts a full ⌘-down / V / ⌘-up sequence
for exactly this reason, but if an app still ignores it, switch
**Settings → Pasting → Deliver text by → Type the text**. That synthesizes the
characters directly and does not depend on the app's paste handling at all.

**Nothing pastes at all, in any app, but "Type the text" works.** The event
tap is swallowing FlowKeys' own synthetic ⌘V. Events posted to
`.cghidEventTap` travel the full input stack and come back through every tap
including ours, so the recursion guard has to hold. If you are hacking on the
paste path and hit this, check `EventTap.suppressSelfGenerated(for:)` is being
called before anything is posted.

To see what the tap is doing:

```bash
log stream --predicate 'subsystem == "com.pg1012.FlowKeys"' --level debug
```

**An app pastes the previous item instead of the one you chose.** It reads the
clipboard lazily, after FlowKeys has already restored your previous contents.
Raise **Settings → Pasting → Restore after**, or turn the restore off.

**System Settings shows FlowKeys enabled, but the app still says it needs
access.** The permission entry is keyed to the app's *code signature*, not its
name or path. FlowKeys is ad-hoc signed, so every rebuild produces a new
signature and orphans the previous entry — which stays in the list, still
switched on, no longer matching the running binary. Toggling it does nothing.

The menu tells you which case you are in: "Access looks granted, but macOS
refused" means the entry is stale. Fix it by removing and re-adding:

1. Select FlowKeys in Accessibility, press **−**
2. Press **+**, add `/Applications/FlowKeys.app`

Or from the terminal:

```bash
make reset-permission     # clears every FlowKeys entry
```

### Making the permission stick across rebuilds

Signing with a stable identity instead of ad-hoc means the entry survives
rebuilds. Create a self-signed code-signing certificate once:

1. Open **Keychain Access** → menu **Certificate Assistant** → *Create a
   Certificate…*
2. Name it `FlowKeys Local Signing`, Identity Type *Self Signed Root*,
   Certificate Type **Code Signing**. Create it.
3. Build with it:

```bash
make install SIGN_IDENTITY="FlowKeys Local Signing"
```

Grant Accessibility once afterwards and it stays granted through future
rebuilds.

---

## How it works

**Capturing copies.** macOS has no "pasteboard changed" notification, so a
timer polls `NSPasteboard.changeCount` four times a second. Content marked
transient or concealed — the flags password managers set — is skipped.

**Intercepting ⌘V.** This is the part that decides whether the idea works at
all. `NSEvent.addGlobalMonitorForEvents` is the obvious API and it is the
wrong one: a global monitor is **passive**. It can watch ⌘V go by but cannot
stop it, so the real paste fires in the frontmost app before you could
possibly substitute a different item.

`CGEvent.tapCreate` with `.defaultTap` can return `nil` from its callback and
swallow the event outright. That is the difference between "hold ⌘ and cycle"
being possible and impossible.

**Pasting.** The chosen text goes on the pasteboard, then a synthetic ⌘V is
posted to the frontmost app, then your previous clipboard contents are put
back. The synthetic event carries a marker in its
`eventSourceUserData` field so FlowKeys' own tap ignores it instead of
recursing.

**Placing the overlay.** It follows the *text caret*, found through the
Accessibility API (`AXFocusedUIElement` → `AXSelectedTextRange` →
`AXBoundsForRange`), falling back to the mouse pointer for apps that expose no
caret. It's a non-activating `NSPanel`, so it can never steal focus from the
app you're about to paste into.

---

## Layout

```
Sources/FlowKeysCore/     Pure logic — no AppKit, fully unit-tested
  CycleSession.swift        the ⌘V state machine
  ClipboardStore.swift      history, dedup, pinning, persistence
Sources/FlowKeysApp/      The macOS app
  EventTap.swift            ⌘V interception
  PasteEngine.swift         pasteboard + synthetic paste
  OverlayPanel.swift        non-activating floating panel
  OverlayView.swift         SwiftUI overlay
  CaretLocator.swift        where to draw it
  ClipboardWatcher.swift    pasteboard polling
```

The interaction logic lives in `FlowKeysCore` with no AppKit imports, so the
behaviour can be tested without a running app or any permissions:

```bash
make test        # 59 tests
```

CI runs the suite, a release build and a bundle verification on every push.

---

## Privacy

Everything stays on your machine. There is no server, no network code and no
telemetry.

That said, a clipboard manager accumulates whatever you copy — which over
time means passwords, tokens and private messages. So:

- History is written to `~/Library/Application Support/FlowKeys/history.json`
  with mode **0600** and the containing directory **0700**, readable only by
  your account. It is also excluded from backups.
- Content flagged transient or concealed is never recorded at all. That is
  the convention password managers use, so 1Password, Bitwarden and friends
  stay out of history by design.
- `ClipboardStore(forgetAfter:)` drops unpinned entries past a chosen age.

**It is not encrypted at rest.** Anything you copy manually — selecting a
password in a text field and hitting ⌘C — is stored in plain text under your
account. If that is not acceptable for your threat model, set
`persistHistory = false` in `Preferences.swift` to keep history in memory
only.

---

## Status

Early but real. What's verified and what isn't:

- ✅ Builds clean, 34 tests pass, app launches as a menu-bar item.
- ✅ Clipboard capture, dedup, ordering and persistence verified end to end.
- ⚠️ The ⌘V interception, cycling and overlay require Accessibility
  permission, which can only be granted by hand in System Settings. They
  are implemented and unit-tested, but the full keystroke path has not been
  exercised on a machine with the permission granted.

Rough edges worth knowing about:

- **Text only.** Images and files aren't captured yet.
- **Ad-hoc signed.** macOS keys Accessibility permission to the code
  signature, and an ad-hoc signature changes on every rebuild. So a rebuild
  orphans the old grant *and* leaves a stale duplicate entry in System
  Settings. Run `make reset-permission` to clear both, then grant once more.
- **Delivery is app-dependent.** Synthetic ⌘V works nearly everywhere, but
  some apps ignore it; the "Type the text" method is the fallback. The
  clipboard-restore window is likewise a timing guess and is now adjustable.
- **No signed release build.** Distributing a `.app` others can open without
  Gatekeeper warnings needs a paid Apple Developer account for notarization.
  Until then, building from source is the supported path.

MIT licensed.

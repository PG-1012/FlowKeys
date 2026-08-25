# FlowKeys

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
| `esc` | Cancel, paste nothing |

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

It starts working the moment you flip the switch — no restart needed.

This is not optional, and it's worth knowing why. Intercepting ⌘V means
*consuming* the keystroke before the frontmost app sees it, and macOS gates
that behind Accessibility. There is no lesser permission that would do.

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
make test        # 34 tests
```

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
- **Ad-hoc signed.** Rebuilding changes the signature, so macOS asks you to
  re-grant Accessibility permission after a rebuild.
- **The clipboard-restore delay is a guess.** After pasting, FlowKeys waits
  250ms before restoring your previous clipboard. Too short and a slow app
  reads an empty pasteboard. Every clipboard manager makes this trade-off;
  the number may need tuning.
- **No preferences UI.** History size and timings are constants in
  `Preferences.swift`.

MIT licensed.

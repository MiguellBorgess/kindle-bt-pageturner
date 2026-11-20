# Kindle BT Page Turner

A [KOReader](https://github.com/koreader/koreader) plugin that turns your
**Bluetooth earbuds into a page turner** on a jailbroken Kindle.

Tap your earbud once, and KOReader goes to the next page. No extra hardware,
no HID remote: it reuses the play/pause button you already have.

## How it works (short version)

When a Bluetooth audio device sends a media command (AVRCP play/pause), the
Kindle's own Bluetooth service broadcasts an internal event called
`BTavrcpCommand`. This plugin listens for that event and asks KOReader to turn
the page.

```
[earbuds] --AVRCP--> [Kindle Bluetooth service] --LIPC event--> [listener.sh] --> [KOReader plugin] --> next page
```

See [How it works](#how-it-works) for the details.

## Will it work on mine?

**Earbuds / headphones:** probably. Any Bluetooth audio device that sends
AVRCP play/pause commands should work. On the tested earbuds, only a **single tap** does;
double tap and long press are handled by the earbuds themselves and never
reach the Kindle.

**Kindle:** confirmed working on the Kindle 11th gen, Paperwhite 5 and
Paperwhite 12th gen. In general, it needs to:

1. have **Bluetooth audio** (models with Audible support, roughly 2017 onwards);
2. be **jailbroken** and running **KOReader**;
3. broadcast the `BTavrcpCommand` event.

See [How to check compatibility](#how-to-check-compatibility) for the details.

## Installation

### Option 1: Storefront (recommended)

The plugin is listed on [Storefront](https://github.com/ultimatejimmy/storefront.koplugin),
a plugin store that runs inside KOReader.

1. Make sure your Kindle is connected to Wi-Fi.
2. In KOReader, open **Tools → Storefront**.
3. Search for `kindle-bt-pageturner` and install it.
4. Restart KOReader when asked.

### Option 2: Manual

1. Download the `btpageturner.koplugin.zip` file from the
   [Releases](https://github.com/migpbor/kindle-bt-pageturner/releases) page.
2. Connect your Kindle to your computer over USB.
3. Copy the `btpageturner.koplugin` folder into `koreader/plugins/` on the
   Kindle:

   ```
   koreader/
   └── plugins/
       └── btpageturner.koplugin/
           ├── _meta.lua
           ├── main.lua
           └── listener.sh
   ```

4. Safely eject the Kindle.
5. Restart KOReader (plugins are loaded on startup).

## Usage

1. Connect your earbuds in the Kindle's Bluetooth settings.
2. Open a book in KOReader.
3. Single-tap your earbud: the page turns.

To uninstall, delete the `koreader/plugins/btpageturner.koplugin` folder.

### Settings

Open a book, then go to the navigation tab of the menu → **BT Page Turner**:

- **Enabled**: turn the plugin on or off. The choice is kept after restarting KOReader.
- **Connected / No device connected**: shows the Bluetooth device the Kindle is connected to.
- **Version**: the installed plugin version.

## How it works

There are three layers between a tap and a page turn.

### 1. Earbuds → Kindle

The earbuds speak **AVRCP**, the Bluetooth profile for media control. A tap
sends a standard command: `0x44` (PLAY) or `0x46` (PAUSE). The tested earbuds
alternate between the two.

On the Kindle, Amazon's Bluetooth service (`acsbtfd`) receives the command
and **publishes** an event called `BTavrcpCommand` on **LIPC**, the Kindle's
publish/subscribe IPC system (built on top of D-Bus). Several Kindle processes
subscribe to it. This plugin simply becomes one more subscriber, without
modifying anything on the system.

### 2. `listener.sh`: the listener

A small shell script running in the background:

- calls `lipc-wait-event` to wait for **one** `BTavrcpCommand` event;
- when it arrives, appends a line to `/tmp/btpageturner.events`;
- loops.

`lipc-wait-event` is deliberately run **without** the `-m` (multiple events)
flag: when its output goes to a file instead of a terminal, it may be
block-buffered and events would show up late. A process that exits always
flushes its output, so starting a new one per event avoids the problem.

The script also traps `TERM` to kill its child process when stopped, and
waits two seconds before retrying if the Bluetooth service is unavailable,
so it never busy-loops.

### 3. `main.lua`: the KOReader plugin

- Starts `listener.sh` when a book is opened and stops it when the book is
  closed (`onCloseDocument`).
- Every 0.3 seconds, checks the **size** of the events file. Each event adds
  2 bytes (`1\n`), so the growth tells how many taps happened since the last
  check.
- For each tap, sends KOReader's `GotoViewRel` event, the same event fired
  when you tap the side of the screen.
- After turning the page, fires KOReader's `InputEvent` hook so the tap counts
  as user activity. Without it, AutoSuspend doesn't see the earbuds as input
  and the Kindle goes to sleep in the middle of reading.
- Ignores taps that happened while the Kindle was asleep (`onResume`), so it
  doesn't skip pages when you wake it up.

At the top of `main.lua`, `POLL_INTERVAL` sets how often the plugin checks
the events file:

```lua
local POLL_INTERVAL = 0.3 -- seconds between checks
```

A lower value makes page turns feel faster, at the cost of slightly more
wake-ups.
The events file lives in `/tmp`, which is kept in RAM on the Kindle, so it
doesn't wear the flash storage.

## How to check compatibility

You can test compatibility before installing anything. You need a terminal on
the Kindle (for example, [kTerm](https://github.com/bfabiszewski/kterm),
available through KPM with `;kpm install kterm`).

1. Connect your earbuds in the Kindle's Bluetooth settings.
2. Open the terminal and run:

   ```sh
   lipc-wait-event -m com.lab126.btfd BTavrcpCommand
   ```

3. Tap your earbud a few times.

If you see lines like these, your Kindle is compatible:

```
BTavrcpCommand 1
BTavrcpCommand 0
BTavrcpCommand 1
```

(Press `Ctrl` + `C` to stop.)

If nothing shows up, first check that the earbuds are still connected: many
earbuds and Kindles drop the connection after a while with no audio playing.

Please open an issue to report results on other devices, working or not.

## License

[AGPL-3.0](LICENSE), the same license as KOReader.

## Acknowledgements

- [KOReader](https://github.com/koreader/koreader)
- [Kindle Modding Wiki](https://kindlemodding.org/) and the jailbreak
  community
- Everyone on [r/kindlejailbreak](https://www.reddit.com/r/kindlejailbreak/comments/1xx722q/)
  who is using the plugin and suggesting improvements


This project was developed with the help of [Claude](https://claude.ai)
(Anthropic), which assisted with analyzing system logs, writing the plugin
code and drafting the documentation. All testing and validation were done
on a real device.

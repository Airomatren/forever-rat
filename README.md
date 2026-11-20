# Forever Rat

A World of Warcraft: Forever addon that clicks the annoying popups for you: resurrections, battle resurrections, summons and group invites. It can also invite people who whisper a keyword, set your group role when you join, and start the combat log in dungeons and raids. Every feature can be turned on or off.

Forever Rat is the WoW: Forever version of [Lazy Rat](https://github.com/Airomatren/Lazy-Rat), with the Retail-only features (queue pops, premade sign-ups, profession gear) taken out.

Type `/fr` or click the minimap button to open the settings.

## Features

### General
- **Auto-accept resurrections:** takes a normal res as soon as it's offered.
- **Auto-accept battle resurrections:** a separate toggle for combat resses. A res counts as a battle res if it comes during a boss encounter or while the caster is in combat.
- **Auto-accept summons:** takes summons automatically. If you're in combat, it waits and accepts as soon as combat ends.
- **Auto combat log in dungeons and raids:** starts the combat log when you enter a dungeon or raid and stops it when you leave. Releasing after a death doesn't stop it, so a corpse run stays in one log. It also turns on advanced combat logging, which Warcraft Logs needs. A log you started yourself with `/combatlog` is never stopped.
- **Minimap button:** click to open settings, drag to move it around the minimap, or hide it.

### Group
- **Auto Invite:** invites anyone who whispers your keyword (`inv` by default, change it in the box). The whole whisper has to be the keyword, in any capitals, so "don't inv me" won't trigger it. Works for normal and Battle.net whispers, and only invites while you're solo, the leader or an assistant. Off by default.
- **Only friends and guild members:** limits Auto Invite to character friends, Battle.net friends and guild members. On by default.
- **Auto Accept:** accepts group invites from character friends, Battle.net friends and guild members. Invites from anyone else still show the normal popup.
- **Auto Role:** sets your group role (Tank, Healer or Damage) once when you join a group, so you can still change it afterwards. The role is **saved per character**, and it's skipped if your class can't fill it. Off by default.

### Notifications
- **Chat message:** prints a line in chat whenever Forever Rat does something for you.
- **Raid warning message:** shows the big message in the middle of your screen as well.

### Early Pull
- **Log early pulls:** when combat starts before a pull countdown reaches zero, Forever Rat logs the date and time, how many seconds early it was, the boss or zone, and who started the countdown. Cancelling a countdown by hand doesn't count.
- **List and export:** the Early Pull tab shows the log, newest first. Click the list to select everything, then press **Ctrl+C** to copy it. Each line also ends with the Unix time and encounter ID, for matching against Warcraft Logs.
- **Clear Data:** empties the log.

All settings except the Auto Role choice are shared across your account.

## Installation

You need **World of Warcraft: Forever**. This addon won't load in Retail or Classic; use [Lazy Rat](https://github.com/Airomatren/Lazy-Rat) for Retail.

### 1. Download

On this page, click the green **Code** button, then **Download ZIP**.

### 2. Find your AddOns folder

The easiest way: open the **Battle.net app**, select **WoW: Forever**, click the **gear icon** next to the Play button and choose **Show in Explorer** (Windows) or **Show in Finder** (Mac). Then open `_forever_` → `Interface` → `AddOns`.

The usual locations are:

| System  | Folder |
|---------|--------|
| Windows | `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns` |
| Mac     | `/Applications/World of Warcraft/_forever_/Interface/AddOns` |

If `Interface` or `AddOns` doesn't exist yet, create it. Spelling and capitals must match.

### 3. Unzip and rename

1. Extract the ZIP. You'll get a folder called **`forever-rat-main`**.
2. **Rename it to `ForeverRat`.** WoW won't load it under the GitHub name.
3. Move the `ForeverRat` folder into `AddOns`.

When you're done, this file should exist:

```
...\_forever_\Interface\AddOns\ForeverRat\ForeverRat.toc
```

A common mistake is a folder nested inside another one, like `AddOns\ForeverRat\forever-rat-main\ForeverRat.toc`. If that happens, move the inner folder up a level.

### 4. Enable it in game

1. Fully restart WoW: Forever if it was open (a `/reload` isn't enough for a newly installed addon).
2. On the character select screen, click **AddOns** (bottom left) and make sure **Forever Rat** is ticked.
3. If it's listed as **Out of date**, tick **Load out of date AddOns** at the top of that window.
4. Log in and type `/fr`.

### Updating

Download the ZIP again and replace the old `ForeverRat` folder. Your settings are kept: WoW stores them in the `WTF` folder, not inside the addon.

### Installing with git (optional)

If you use git, clone straight into the right folder name and run `git pull` to update:

```
cd "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"
git clone https://github.com/Airomatren/forever-rat.git ForeverRat
```

## Shoutout

Big thanks to **Noobheartx** and [MythicPlusCount](https://github.com/noobheartx/MythicPlusCount) (MIT licensed). The settings window copies its look. Go check it out.

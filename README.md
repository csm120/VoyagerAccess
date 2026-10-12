# Voyager Access

Voyager Access makes Star Trek: Voyager - Across the Unknown playable with a screen reader. It speaks the menus, dialogue, tutorials, objectives, ship rooms, the System Map, point of interest events and your resources through NVDA or JAWS, and adds keyboard controls where the game only offers a mouse or a controller.

So far it has been tested on the opening of the free Steam demo; the full game should work too. This is an early version, built by a blind player for blind players, so expect gaps. If something is silent or a key does nothing, please tell us.

## Not official

Voyager Access is a free, unofficial fan project. It is not made, endorsed or supported by Daedalic Entertainment, gameXcite, CBS Studios or Paramount. Star Trek and related marks are trademarks of CBS Studios Inc. Voyager Access does not include any of the game's files; you need your own copy of the game from Steam.

## What you need

1. Windows 10 or 11, 64-bit.
2. Star Trek: Voyager - Across the Unknown, or its free demo, installed through Steam.
3. NVDA or JAWS running. Without a screen reader, Windows' own speech is used.

## Installing

1. [Download the Voyager Access installer](https://github.com/csm120/VoyagerAccess/releases/latest/download/VoyagerAccessSetup.exe). This link always gets the newest version.
2. Open the file you downloaded. If Windows says "Windows protected your PC", choose More info, then Run anyway. (Windows says this because the installer is not signed by a paid certificate.)
3. The installer finds the game in Steam and adds Voyager Access to it, then tells you when it is ready.
4. Start the game from Steam as usual. Speech starts when the game loads.

Along the way, Steam closes for a moment and starts again by itself; there is nothing to answer. Voyager Access does that to set the game's launch options in Steam, so that it starts together with the game, and to set the game to use DirectX 11, because some computers crash when it uses DirectX 12. If you are playing another game through Steam at that moment, it waits until that game closes.

If the game is not installed yet, the installer offers to open Steam's install window for the free demo, or the store page for the full game.

After that, there is nothing to look after. Voyager Access starts when you start the game from Steam and closes when the game closes; nothing of it runs when you are not playing. If a game update removes it, it puts itself back before the game starts. Uninstalling it puts the game's launch options back the way they were.

Voyager Access also keeps itself up to date. It checks for a new version when the game starts and every 10 minutes while you play:

1. If an update turns up in the first minute, while you are still at the main menu, the game closes, updates and starts again by itself.
2. If one turns up later, you hear that it is ready. It installs when you close the game, or press F12 to restart and install it now. The game only saves at story points, so it is never closed unless you press F12.
3. After an update you hear which version you now have.

## Keys

Press F1 anywhere in the game to hear the keys for the screen you are on.

Everywhere:

1. F1: help for this screen.
2. O: your current objective.
3. C: your resources (cargo), crew, and how long your fuel lasts.
4. V: switch between the ship and the System Map.
5. R: repeat the last line, tutorial or window.
6. F12: check for a Voyager Access update now. If one is found, you hear that it is ready; press F12 again to restart the game and install it.

Menus and settings:

1. Up and Down Arrow move through the items; Home and End go to the first and last.
2. Enter selects. Backspace goes back.
3. Left and Right Arrow change a setting's value.

Dialogue and cutscenes:

1. Enter continues. When choices appear, Up and Down Arrow move between them and Enter picks one.
2. Shift+Enter skips ahead in a dialogue, or skips a cutscene.

Ship view:

1. Up and Down Arrow change deck; Left and Right Arrow move between the rooms on a deck.
2. Home and End go to the first and last room on the deck.
3. Enter opens the room. Its window reads its state, and each button reads what it costs and why it cannot be used yet. Left and Right Arrow switch the room's tabs. Escape closes the room.

System Map:

1. Up and Down Arrow move through the points of interest, nearest first. Each says whether it has been scanned and what it holds.
2. Enter opens a list of actions: Scan, or Set course.

Point of interest events: each option reads its reward, its risk, and its chances of a good or bad outcome. Locked options are read when the event opens, and with R.

Tutorials are read aloud and then closed for you. R repeats the last one.

## Uninstalling

Use Windows Settings, Apps, Installed apps, Voyager Access, Uninstall. The uninstaller takes Voyager Access out of the game folder and puts back anything it replaced, removes the DirectX 11 setting if it added it, and leaves the game exactly as it was.

## License

Voyager Access's own code is under the MIT License (LICENSE). It includes RE-UE4SS, Tolk and the NVDA Controller Client under their own licenses; see THIRD-PARTY-NOTICES.txt.

## For developers

The mod is UE4SS Lua in mod/VoyagerAccess. The Windows program that speaks, reads keys and installs is Python in voyager/. Keyboard rules are in docs/keyboard.md, and the installer build in installer/. Building needs the UE4SS release zip and Tolk's DLLs in a vendor/ folder (see installer/build_payload.py and installer/VoyagerAccess.spec).

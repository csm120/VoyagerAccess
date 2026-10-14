# Voyager Access

Voyager Access makes Star Trek: Voyager - Across the Unknown playable with a screen reader. It speaks the menus, dialogue, tutorials, objectives, ship rooms, the System and Sector Maps, point of interest events, away missions, battles, the tech tree, side mission requests and your resources through NVDA or JAWS, and adds keyboard controls where the game only offers a mouse or a controller, such as building rooms and giving orders in battle.

The whole free Steam demo has been played through to its end with it; the full game should work too. It is built by a blind player for blind players, so expect a few gaps. If something is silent or a key does nothing, please tell us.

## Not official

Voyager Access is a free, unofficial fan project. It is not made, endorsed or supported by Daedalic Entertainment, gameXcite, CBS Studios or Paramount. Star Trek and related marks are trademarks of CBS Studios Inc. Voyager Access does not include any of the game's files; you need your own copy of the game from Steam.

## What you need

1. Windows 10 or 11, 64-bit.
2. Star Trek: Voyager - Across the Unknown, or its free demo, installed through Steam.
3. NVDA or JAWS running. Without a screen reader, Windows' own speech is used.

## Installing

1. [Download the Voyager Access installer](https://github.com/csm120/VoyagerAccess/releases/latest/download/VoyagerAccessSetup.exe). This link always gets the newest version.
2. Open the file you downloaded. The installer is signed by Web Friendly Help LLC. Windows may still say "Windows protected your PC" for a while, because the download is new to it; if it does, choose More info, check that the publisher is Web Friendly Help LLC, then choose Run anyway.
3. The installer finds the game in Steam and adds Voyager Access to it, then tells you when it is ready.
4. Start the game from Steam as usual. Speech starts when the game loads.

Along the way, Steam closes for a moment and starts again by itself; there is nothing to answer. Voyager Access does that to set the game's launch options in Steam, so that it starts together with the game, and to set the game to use DirectX 11, because some computers crash when it uses DirectX 12. If you are playing another game through Steam at that moment, it waits until that game closes.

If the game is not installed yet, the installer offers to open Steam's install window for the free demo, or the store page for the full game.

After that, there is nothing to look after. Voyager Access starts when you start the game from Steam and closes when the game closes; nothing of it runs when you are not playing. If a game update removes it, it puts itself back before the game starts. Uninstalling it puts the game's launch options back the way they were.

Voyager Access also keeps itself up to date. It checks for a new version when the game starts and every 10 minutes while you play:

1. If an update turns up in the first minute, while you are still at the main menu, the game closes, updates and starts again by itself.
2. If one turns up later, you hear that it is ready. It installs when you close the game, or press F12 to restart and install it now. The game only saves at story points, so it is never closed unless you press F12.
3. After an update you hear which version you now have.

## What's new

Every release is described in plain words in [What's new in Voyager Access](docs/WHATS_NEW.md), newest first.

## Keys

Press F1 anywhere in the game to hear the keys for the screen you are on. Press Control+F1 for a list of every key, grouped by screen, which you move through with Up and Down Arrow; Escape or Backspace closes it.

Everywhere:

1. F1: help for this screen. Control+F1: every key.
2. L: where you are and what is selected.
3. O: your current objective. In a battle, the battle's goal.
4. C: hull, resources (cargo), crew, work teams, fuel, energy, battery and morale, as a list.
5. N: a list of places to go: ship, System Map, Sector Map, Overview, Research, and Wait one cycle.
6. V: switch between the ship and the System Map.
7. R: repeat the last line, tutorial or window.
8. Escape: the game's own back and pause menu. It also closes any list Voyager Access opened.
9. F12: check for a Voyager Access update now. If one is found, you hear that it is ready; press F12 again to restart the game and install it.
10. Control+F12: what's new in Voyager Access.
11. Backtick (the key left of 1): copy a troubleshooting report to the clipboard.

Menus and settings:

1. Up and Down Arrow move through the items; Home and End go to the first and last.
2. Enter selects. Backspace goes back.
3. Left and Right Arrow change a setting's value, or switch a window's tabs.

Dialogue and cutscenes:

1. Enter continues. When choices appear, Up and Down Arrow move between them and Enter picks one. A major decision, which the game wants held down, is held for you.
2. Shift+Enter skips ahead in a dialogue, or skips a cutscene.

Ship view:

1. Up and Down Arrow change deck; Left and Right Arrow move between the rooms on a deck.
2. Home and End go to the first and last room on the deck.
3. J: a list of all the ship's rooms with their deck and state; Enter goes to one.
4. Enter opens the room. Its window reads its state and the energy it uses, and each button reads what it costs and why it cannot be used yet. Left and Right Arrow switch the room's tabs. Escape closes the room.
5. A ruined room or empty building space opens a ring of actions; Up and Down Arrow move through it and Enter picks one. On empty space, each room you could build says how many spaces wide it is and whether it fits there, and Enter builds it. Escape closes the ring.

System Map and Sector Map:

1. Up and Down Arrow move through the points of interest, or the star systems on the Sector Map. Each says whether it has been scanned and which resources it has.
2. Enter opens a list of actions: Scan, or Set course. While you travel you hear when you are under way, halfway and arrived; L adds the trip's progress.

Point of interest events: each option reads its reward, its risk, and its chances of a good or bad outcome. Locked options are read when the event opens, and with R.

Tech tree (from the Science Laboratory, or Research in the N list): Up and Down Arrow move through the tiers and technologies, Left and Right Arrow switch category, and Enter opens one, reading its cost and description; Enter again begins the research.

Away missions: Up and Down Arrow move through the choices, the heroes for each and Confirm; each choice reads the skill it needs, its reward and its danger. Enter picks a hero or confirms. The result and the mission summary are read for you.

Battles: Enter opens Orders, and the order wheel is a list (attack a system of the enemy ship, defend a side, repair, flee). L reads both ships, the enemies, your order, torpedoes, the heroes' abilities and the goal. The game's own keys work too: Space pauses, 1 to 3 use the heroes' abilities, Tab changes target, Shift fires a torpedo. Target changes, abilities becoming ready, and pauses are spoken as they happen.

Side mission requests read who is asking, what they want and the time limit, then the choices.

Tutorials are read aloud and then closed for you. R repeats the last one.

## Uninstalling

Use Windows Settings, Apps, Installed apps, Voyager Access, Uninstall. The uninstaller takes Voyager Access out of the game folder and puts back anything it replaced, removes the DirectX 11 setting if it added it, and leaves the game exactly as it was.

## License

Voyager Access's own code is under the MIT License (LICENSE). It includes RE-UE4SS, Tolk and the NVDA Controller Client under their own licenses; see THIRD-PARTY-NOTICES.txt.

## For developers

The mod is UE4SS Lua in mod/VoyagerAccess. The Windows program that speaks, reads keys and installs is Python in voyager/. Keyboard rules are in docs/keyboard.md, and the installer build in installer/. Building needs the UE4SS release zip and Tolk's DLLs in a vendor/ folder (see installer/build_payload.py and installer/VoyagerAccess.spec).

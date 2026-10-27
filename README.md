# Voyager Access

Voyager Access makes Star Trek: Voyager - Across the Unknown playable with a screen reader. It speaks the menus, the difficulty and Q Trials setup screens, dialogue, tutorials, objectives, ship rooms, the System and Sector Maps, point of interest events, away missions, battles, the tech tree, side mission requests and your resources through NVDA or JAWS, and adds keyboard controls where the game only offers a mouse or a controller, such as building rooms and giving orders in battle.

The whole free Steam demo has been played through to its end with it, and it works with the full game too. It is built by a blind player for blind players, so expect a few gaps. If something is silent or a key does nothing, please tell us.

## Not official

Voyager Access is a free, unofficial fan project. It is not made, endorsed or supported by Daedalic Entertainment, gameXcite, CBS Studios or Paramount. Star Trek and related marks are trademarks of CBS Studios Inc. Voyager Access does not include any of the game's files; you need your own copy of the game from Steam.

## Getting started

Voyager Access does not include the game. You get the game from Steam first, then add Voyager Access to it.

1. Make sure you have Windows 11 (64-bit), which is what Steam lists for the game, and NVDA or JAWS running. Without a screen reader, Windows' own speech is used.
2. If you don't have Steam yet, [get Steam from its official site](https://store.steampowered.com/about/), install it and sign in. A Steam account is free.
3. In Steam, install [Star Trek: Voyager - Across the Unknown](https://store.steampowered.com/app/2643390/). You can buy the full game, or install the free demo from the same store page; Voyager Access works with either.
4. Once the game (or the demo) has finished installing, install Voyager Access as described in the next section.

Already ran the Voyager Access installer before you had the game? That's fine. Once the game is installed, open the Start menu, go to Voyager Access, and choose "Add Voyager Access to the game", which adds it and starts the game. Running the installer again works too.

## Installing

1. [Download the Voyager Access installer](https://github.com/csm120/VoyagerAccess/releases/latest/download/VoyagerAccessSetup.exe). This link always gets the newest version.
2. Open the file you downloaded. The installer is signed by Web Friendly Help LLC. Windows may still say "Windows protected your PC" for a while, because the download is new to it; if it does, choose More info, check that the publisher is Web Friendly Help LLC, then choose Run anyway.
3. The installer finds the game in Steam and adds Voyager Access to it, then tells you when it is ready.
4. Start the game from Steam as usual. Speech starts when the game loads.

While the installer adds Voyager Access to the game, Steam closes for a moment and starts again by itself. You don't need to answer anything. The installer does this to change two things in the game's launch options in Steam:

1. Voyager Access starts whenever you start the game.
2. The game uses DirectX 11, because some computers crash when it uses DirectX 12.

If you are playing another game through Steam at that moment, the installer waits until that game closes.

If the game is not installed yet, the installer says so and offers to open the game's page in Steam. Install the game, then add Voyager Access as described under Getting started.

You don't need to do anything after installing:

1. Voyager Access starts by itself when you start the game from Steam, and stops when you close the game. Nothing of it runs when you are not playing.
2. If a game update removes Voyager Access from the game, Voyager Access puts itself back before the game starts.
3. If you uninstall Voyager Access, the game's launch options in Steam go back to how they were before you installed it.

Voyager Access also keeps itself up to date. It checks for a new version when the game starts, and every 10 minutes while you play. When it finds one:

1. If it finds the update right after the game starts, it waits for the main menu, then closes the game, updates and starts it again by itself. If you have already loaded a game by then, it leaves your game alone and works as in step 2.
2. Otherwise you hear that the update is ready. It installs when you close the game, or you can press F12 to restart the game and install it right away. Because the game only saves at story points, Voyager Access never closes a game you are playing unless you press F12.
3. After an update, you hear which version you now have.

## What's new

Every release is described in plain words in [What's new in Voyager Access](docs/WHATS_NEW.md), newest first.

## Keys

Press F1 anywhere in the game to hear the keys for the screen you are on. Press Control+F1 for a list of every key, grouped by screen, which you move through with Up and Down Arrow; Backspace closes it.

Everywhere:

1. F1: help for this screen. Control+F1: every key.
2. I: where you are and what is selected.
3. O: your current objective. In a battle, the battle's goal.
4. C: hull, resources (cargo), crew, work teams, fuel, energy, battery and morale, as a list.
5. N: a list of places to go: ship, System Map, Sector Map, Overview, Research, and Wait one cycle.
6. V: switch between the ship and the System Map.
7. R: repeat the last line, tutorial or window.
8. Escape: the game's own back and pause menu, just as for anyone else. Backspace closes a list Voyager Access opened without bringing up the pause menu.
9. F12: check for a Voyager Access update now. If one is found, you hear that it is ready; press F12 again to restart the game and install it.
10. Control+F12: what's new in Voyager Access.
11. Backtick (the key left of 1): copy a troubleshooting report to the clipboard.

Menus and settings:

1. Up and Down Arrow move through the items; Home and End go to the first and last. At either end of a list, the arrow says the item you are on again.
2. Enter selects. Backspace goes back.
3. Left and Right Arrow change a setting's value, or switch a window's tabs.

Starting a game in the full game:

1. On the main menu, Enter on CAMPAIGN (or Q TRIALS) opens three profiles. Enter on a profile, then on NEW CAMPAIGN (or NEW Q TRIAL).
2. The difficulty window is a list of the four modes, each read with its description and what it changes. Enter on a mode starts the game.
3. Custom opens Custom Difficulty Settings: Up and Down Arrow move through the three presets, every setting with its value and description, and Start Game. Left and Right Arrow change a setting. Enter on Start Game holds it down for you. Escape goes back.

Q Trials setup: the ship and its numbers are read when the setup opens, and Left and Right Arrow change ship. Up and Down Arrow move through the captain, the hero slots, the Q Modifier, the Q Challenges level and Start Game. Enter on any of them opens its list of choices, and Enter picks one; locked choices say so. In the hero list, Enter chooses or removes a hero and says how many you have, and Confirm closes the list.

Dialogue and cutscenes:

1. Enter continues. When choices appear, Up and Down Arrow move between them and Enter picks one. A major decision, which the game wants held down, is held for you.
2. Shift+Enter skips ahead in a dialogue, or skips a cutscene. A story card, like "Into the Badlands", has nothing to skip to, so there Shift+Enter just reminds you that Enter continues.
3. Narration over a scene, like the start of a new campaign or a Q Trial, is read a line at a time. Shift+Enter skips it.

Ship view:

1. Up and Down Arrow change deck; Left and Right Arrow move between the rooms on a deck.
2. Home and End go to the first and last room on the deck.
3. J: a list of all the ship's rooms with their deck and state; Enter goes to one. Page Up, Page Down, Left or Right Arrow close the list and move in the ship view.
4. Enter opens the room. Its window reads its state and the energy it uses, and each button reads what it costs and why it cannot be used yet. Left and Right Arrow switch the room's tabs. Escape closes the room.
5. A ruined room or empty building space opens a ring of actions; Up and Down Arrow move through it and Enter picks one. On empty space, each room you could build says how many spaces wide it is and whether it fits there, and Enter builds it. Escape closes the ring.
6. The game's own room keys act on the room you moved to, and each room says which it offers: E is its quick action, F upgrades it and T demolishes it. A tap of E switches power; repairing, clearing debris, upgrading and demolishing take the key held down, so those rooms say "Hold E: Repair" or "Hold F: Upgrade".

System Map and Sector Map:

1. Up and Down Arrow move through the points of interest, or the star systems on the Sector Map. Each says whether it has been scanned and which resources it has.
2. Enter on the System Map picks the place in the game, so you hear the game's own details for it, then "Menu" and a list of actions: Scan, or Set course. On the Sector Map Enter goes straight to the list. Set course puts the pointer on the place and holds the game's own Set course, the way a mouse player does; if the game doesn't take it after two tries, the mod asks the game to fly there directly. While you travel you hear when you are under way, halfway and arrived; I adds the trip's progress.

Point of interest events: each option reads its reward, its risk, and its chances of a good or bad outcome. Locked options are read when the event opens, and with R.

Tech tree (from the Science Laboratory, or Research in the N list): Up and Down Arrow move through the tiers and technologies, Left and Right Arrow switch category, and Enter opens one, reading its cost and description; Enter again begins the research. R repeats where you are, Backspace closes the tree, and C tells you resources aren't shown there.

Away missions: on the team selection, Up from the first slot goes through the recommended skills, traits and each challenge, one line at a time. In the mission itself, each choice is a task, and Up and Down Arrow move through the tasks, the heroes under each and its Lock In or Confirm. A task line says the skill and the number it needs, its reward and any danger ("Task 3 of 3: Break the illusion of the wall. Engineering 30. Reward 150 Deuterium. Select one or more heroes below."), and a choice the game outlines in gold says "Major decision"; each hero says only their own number ("Harry Kim, 25"), so you can compare them. Left and Right Arrow, or Page Up and Page Down, jump between tasks. Enter selects or removes a hero, or confirms. With two or more heroes on a task you hear the team's total, and the chance is said as "Will succeed" with the chance of a critical success, or as a success chance when the team falls short. The result and the mission summary are read for you.

Battles: Enter opens Orders, and the order wheel is a list (attack a system of the enemy ship, defend a side, repair, flee). I reads both ships, the enemies, your order, torpedoes, the heroes' abilities and the goal. The game's own keys work too: Space pauses, 1 to 3 use the heroes' abilities, Tab changes target, Shift fires a torpedo. Target changes, abilities becoming ready, pauses, each ship's hull dropping past 75, 50, 25 and 10 percent, and an enemy shield side going down are spoken as they happen.

Side mission requests read who is asking, what they want and the time limit, then the choices.

Tutorials are read aloud and stay open until you press Enter, so R can read them again. While one is open, the arrow keys remind you that Enter closes it. A tutorial that opens on top of a window is read first, then the window behind it.

What the mod says on its own (a scan result, an objective, a conversation that starts by itself) isn't cut off by the next thing it says on its own; any key you press still cuts it off, except your screen reader's own commands (NVDA+Up Arrow and the like).

## Uninstalling

Use Windows Settings, Apps, Installed apps, Voyager Access, Uninstall. The uninstaller takes Voyager Access out of the game folder and puts back anything it replaced, removes the DirectX 11 setting if it added it, and leaves the game exactly as it was.

## License

Voyager Access's own code is under the MIT License (LICENSE). It includes RE-UE4SS, Tolk and the NVDA Controller Client under their own licenses; see THIRD-PARTY-NOTICES.txt.

## For developers

The mod is UE4SS Lua in mod/VoyagerAccess. The Windows program that speaks, reads keys and installs is Python in voyager/. Keyboard rules are in docs/keyboard.md, and the installer build in installer/. Building needs the UE4SS release zip and Tolk's DLLs in a vendor/ folder (see installer/build_payload.py and installer/VoyagerAccess.spec).

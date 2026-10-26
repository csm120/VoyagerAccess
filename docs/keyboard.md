# Keyboard rules for Voyager Access

Casey's rules for how the mod's keys behave (2026-10-10). Every new screen
follows them.

1. Anything that is a list moves with Up and Down Arrow: menus, settings,
   rooms, points of interest, action lists. This is true whatever the screen's
   layout: a screen reader user cannot tell whether things sit side by side
   or one above another (Casey, 2026-10-11), so a row of buttons is a list
   too. focus.lua enforces it: when Up or Down leaves focus where it was, the
   mod moves to the previous or next on-screen button of the same window.
   Only true grids (ship decks and rooms) use Left and Right to move.
2. Home and End go to the top and bottom of any list or menu, unless the game
   itself uses the key there. (Checked 2026-10-10: the game binds neither
   anywhere.)
3. Left and Right Arrow change a value (settings), and are not used to move
   through lists. Exception: the ship view is a grid, so Up and Down change
   deck and Left and Right move along it (Casey, 2026-10-11: Page Up and Page
   Down are hard to find on laptops).
4. Enter does the selected thing. Where a thing has more than one action,
   Enter opens a short list of its actions instead.
5. Backspace goes back, or closes a list the mod opened. Escape is the
   game's: it opens the pause menu where the game does. If a list the mod
   opened is up, Escape closes it too, and the pause menu stays (Casey,
   2026-10-23: the mod no longer clicks it away).
6. F1 says the keys for the current screen. No "Press F1 for help" hint is
   spoken on screens (Casey, 2026-10-11: it repeated on every screen).
7. O reads the current objective; C reads the resources (cargo) as a list,
   and Enter on a line lists its details as the game's tooltip shows them
   (description, capacity, production, morale's causes and reachable
   maximum, threat against your strength; Backspace goes back); R repeats the
   last line, tutorial or card; R again within 5 seconds goes back one message
   further each time ("Earlier: ..."). After the first reading, objectives announce
   only what changes ("Done: ...", "Mission ended: ...", "New mission: ...");
   O reads the whole list. C also says each resource's storage limit, for
   example "Duranium 100, max 100".
8. Never describe anything by color. A chance bar is read as its outcomes and
   their chances (excellent, good, average, bad, terrible), after the
   rewards, worded "70% chance of a good outcome, 30% chance of a bad
   outcome" (Casey, 2026-10-11), rounded to fives. No summary word goes in
   front: the bar has none (Casey, 2026-10-23). A bar with one outcome is
   not read.
9. A key the mod uses must be unbound in the game in that context
   (the game's own key bindings), because the game also receives it.
10. Key hints the mod adds to a reading ("Left and Right choose another",
   "R repeats the line", "Enter to choose a hero") are said the first two
   times only, counted across sessions in hints.txt; F1 and Ctrl+F1 still list
   every key (Casey, 2026-10-19: "once or twice is fine").

## Keys in use

1. Everywhere: F1 help, O objective, C resources, energy and morale, V ship view or System Map, N navigation list, H a waiting call,
   I where am I, R repeat, Ctrl+F12 what's new (a list, like C), Ctrl+F1 every key (a list, grouped by screen; hotkeys.lua keeps it in step with this file). Backtick (the key left of 1) copies a report for
   troubleshooting to the clipboard (the helper's job, like F12). F12 belongs to the helper, not the mod: after an
   update is offered it restarts the game to install it; otherwise it checks for an update
   now and says what it found (a found update is offered, never installed
   by that same press).
2. Menus and settings: Up, Down, Home, End, Enter, Backspace; Left and Right
   change a setting. Menu items and room buttons say their position, for
   example "Dismantle, 2 of 3".
3. Dialogue: Enter continues, Shift+Enter skips ahead. On a line with no
   choices, Up, Down, Home and End say the line again ("Enter continues."
   the first times). When a call comes in, the mod says "Incoming call. To
   answer, press H, then Enter." H, in the ship view or System Map, opens
   the waiting call as a click on the game's call button does; Enter on the
   call ("Incoming call: <name>") starts the conversation. With no call, H
   says "No incoming call". N still lists "Incoming calls" while a call is
   waiting, in the game's own order.
4. Cutscene: Shift+Enter skips.
5. Ship view: Up and Down (or Page Up and Page Down) change deck, Left and
   Right move along it, Home and End go to the ends of the deck, Enter opens
   a room. In a room window: Up and Down through its buttons, Left and Right
   switch tabs, Escape closes it (the game's own Escape). Closing a room's
   hero list without choosing, with Backspace or Escape, takes the hero out
   of the room, as the game does; the mod says "removed" (Casey,
   2026-10-23). Sickbay's Manage Patients tab reads
   each patient with their condition and the cycles to recover; a quarters
   room's Crew Info tab reads its inhabitants with their condition and
   where they work; the Bridge's
   Combat Allies tab reads the ally's combat power, recruitment cost and
   upkeep. Rooms say their
   place on the deck ("3 of 6"). J lists the ship's rooms (not ruined rooms
   or turbolifts) with deck and state; Up, Down, Home, End, Enter selects
   the room, Backspace or J closes the list (J is unbound in
   IMC_ShipManagement). A ruined room opens an action ring (radial menu):
   its centre is read, Up and Down move through its segments, Enter does
   the focused one, Escape closes it. Empty building space opens the
   construction ring; a room in it says how many spaces wide it is and
   whether it fits here, and Enter builds it at the selected space.
   The game's own room keys act on the room you last moved to: E is the
   room's quick action (power on or off, repair, clear debris, or pause
   work); hold F to upgrade it, or hold T to demolish it. The game takes
   repair, clear debris, upgrade and demolish only with the key held, about
   two thirds of a second; power and pause are a tap. Moving to a room
   says the room, its deck and state at once; once the game's info panel
   shows the room (the camera has reached it), it says each action the game
   offers there, with its key and cost, like
   "E: Toggle Power", "Hold E: Repair", "Hold F: Upgrade" or "Enter: Build
   Room" on an empty space. Moving to a room puts the
   mouse pointer on it, and the camera goes to it when it is off screen.
   Press I twice for the room's details as a list: what the game's info
   panel shows when you point at the room (level, energy, crew, and what E
   does there and costs). Up, Down, Home and End move; Backspace closes it.
6. System map: Up and Down through the points of interest, Home and End,
   Enter selects the point in the game, as a click on it does, so the game's
   own detail panel opens and is read (name, system, zone, resources), then
   opens the action list (Scan, Set course, and the panel's third button,
   Inspect, under the game's own name when the game shows it). Inspect opens
   the game's close view of the point, which has no text; Backspace leaves
   it. The list keeps its order
   while you move through it (it re-sorts nearest first after 15 seconds
   without a move). Set course says "Under way to", "Halfway to" and
   "Arrived at"; I adds the trip's progress and says "not moving" if the
   ship has stopped short. A point whose events are all over says "done";
   arriving there again opens nothing. Arriving at any other point opens its
   event by itself. When the chosen point is off screen (after story
   scenes, for example), Set course zooms the map out by itself first. In an event at a point of interest, Up and Down
   move through the options; where an option can take a hero (Q Trials),
   the option names the hero the game will send (it starts on the best
   available one). Left and Right move the game's own choice of hero and say
   the hero it moved to, with the chances the game's bar shows for that hero,
   and Enter carries the option out with that hero.
7. Main menu Credits: a list, one heading with its names per item; Escape
   closes it. In the main menu's save window, Enter on Restart Sector or
   Delete Profile opens its confirmation, which is read, with BACK and
   ACCEPT as a list.
8. Tech tree (Science Laboratory, Research): a list of the five tiers, then
   the current category's technologies in tier order, each with its state,
   what it builds on (the lines between fields on screen), and whether the
   game marks it important or as unlocking a feature.
   Each tier names the technologies it opens.
   Past the last category and before the first, Left and Right reach one
   more list: every category's technologies from A to Z, each with its
   category; Enter there moves to that technology in its category and opens
   its panel.
   Up, Down, Home, End move; Left and Right switch category; Enter opens the
   item's panel, which is read (costs, description, and whether Enter begins
   the research); Escape closes the panel, then the tree. Backspace closes
   the tree when no panel is open (with a panel open it says that Escape
   closes the panel). R repeats the item (the game closes an open panel on R).
9. Overview (N, Overview): Left and Right switch tabs, and each tab is read when it opens.
   Up and Down go through the open tab line by line, one row per item (a
   morale condition with its crew and max morale, a threshold with its
   effects, a combat room with its count and power); Home and End go to the
   ends, and Enter repeats the line. On the Heroes tab, Up and Down choose a
   hero and read their details. Escape closes the Overview.
10. Combat: the game's own keys work (Space pauses and resumes, 1 to 3 use
   the heroes' abilities, Tab changes target, Shift fires a torpedo, Left
   and Right pick a system and Up and Down move energy to it). Enter opens
   Orders; the order wheel is a list (Up, Down, Enter; Back is last). I
   reads both ships, the enemies, the order, torpedoes, abilities, energy and
   the goal; O reads the goal. Target changes, abilities turning active or
   ready, pauses and energy ("Engine 1 of 2, 2 spare") are spoken as they
   happen.
11. Away team selection: Enter on a slot chooses or changes its hero. Once
    every slot is filled, filled slots say "Team complete: End moves to
    Start Mission"; Enter on Start Mission (also Down from the last slot)
    starts the mission. Up from the first slot goes through the
    mission's recommended skills, each recommended trait and each challenge
    as lines; Up and Down move, Home goes to the first line, and Down from
    the last line or End goes back to the slots. Heroes in a mission choice say when they have
    the trait the choice asks for ("has the Pilot trait").

# New in Voyager Access

## Friday October 16th 2026

Version 0.3.35

A crash fix.

- Fixed: the game could crash right after you closed a report, like the Construction Report, when another message opened at the same moment. In testing it crashed 7 times out of 10 that way, and not once in 5 tries after the fix.

## Friday October 16th 2026

Version 0.3.34

Room tabs, hull repair and the Bio Laboratory.

- Fixed: after switching tabs in a room's window, the arrows could stay stuck on the tab you left. The Engineering Office's Work Team Info tab, where work teams are put on hull repair, couldn't be reached at all. The new tab's buttons now take the arrows.
- Changed: the Work Team Info tab says how fast the hull is being repaired and what it costs, along with the hull itself, like "Hull repair per cycle +3 hull, -1 duranium. Hull 9, -9 per cycle."
- Changed: the Bio Laboratory reads what it's making and its blueprints, like "1 bio-neural gel pack, selected. Costs 120 food, 20 duranium. 20 cycles". Before, it said "+1, 20, 120".
- Fixed: in battle, L said "X torpedoes" when the torpedo bay wasn't working. It says "no torpedoes" now.
- Fixed: the warning about empty hero slots before a battle said "Continue" before its message.

## Friday October 16th 2026

Version 0.3.33

Restart Sector, the Sickbay and a few readings.

- Fixed: in a profile's menu, Restart Sector only said "selected" and nothing opened, so after a game over there was no way back to a sector's start. One Enter now opens the list of sector saves, like "Sector 1, Caretaker".
- Changed: the Sickbay reads its patients when it opens, with each one's condition and the cycles until they recover, and says which ones are heroes. Before, a Sickbay full of patients only said its name and energy.
- Changed: a room with paused work says so, like "Ruined room, removing, paused, 3 cycles".
- Fixed: when an objective's count changed, like "Treat the sick before the disease spreads (38)" going to 45, it was announced as done and then as a new objective. Count changes are quiet now, and O reads the current numbers.
- Fixed: square brackets around names were still read in some messages, like "[Sick bay] got damaged". An "&" in the game's text is read as "and".

## Friday October 16th 2026

Version 0.3.32

Building rooms where they really fit.

- Fixed: the build ring treated every room as 2 spaces wide, so rooms like the Phaser Control Room, the Bio Laboratory and the Cargo Bay said they fit when they didn't, and Enter did nothing. Each room now says its real size, like "4 spaces wide, does not fit" or "3 spaces wide and 3 decks tall", and Enter only builds it where it really fits.
- Fixed: Backspace in the build ring goes back to the categories. Before, it said "Nothing to go back to".
- Fixed: a few room descriptions read square brackets around names, like "the [TECH TREE]". The brackets are gone.
- Fixed: in a room's hero list, pressing Enter on a hero you can't pick and then backing out emptied the room's slot. The room keeps its hero now.

## Friday October 16th 2026

Version 0.3.31

More fixes for games in other languages.

- Fixed: in a game set to another language, event results read the reward share the English version leaves out, like "65% Belohnungsverteilung", and named the total oddly. They read the same way as in English now, like "Outcome: gut. 454 deuterium stored."

## Friday October 16th 2026

Version 0.3.30

Away missions in any language, and choices you can't take.

- Fixed: if your game is set to a language other than English, away missions couldn't be finished. Picking a hero never said "selected", and Confirm kept saying to select a hero first. They work in every language now, including the cornfield on the first away mission. Tired heroes are called fatigued in every language too.
- Fixed: in a conversation, choices you can't take were skipped by the arrows and never read. Now the first time the choices come up you also hear the ones that aren't available and why, like "Not available: Choice 1: Block the asteroid with Voyager. Needs Shield Generator Level 0".
- Changed: on an away mission, if a hero can't take a choice because it needs a certain trait, Enter tells you, like "Kes cannot take this choice: it needs a hero with the Talaxian trait". Before, nothing happened.

## Friday October 16th 2026

Version 0.3.29

Q Trials modifiers, scans, counts and a few safety nets.

- Fixed: the Q Modifier cards at the end of a Q Trials sector only said "Q Modifier". They read their name and what they do now, like "Party Ship. Grants a permanent morale bonus of +20 per cycle but increases the time to build, repair, upgrade or deconstruct rooms by 100%." Pressing Enter on the card you already chose takes it back, and it says so.
- Changed: when a scan doesn't go through, it tells you why, like "the scanner needs a working Stellar Cartography".
- Changed: if the game's language changes, you hear it, like "Game language changed to Spanish". Moving through the Language setting switches the language right away, so it's easy to land in another one by accident.
- Fixed: counts are right where a list sits beside a single button. The graphics choices you get on first start said "4 of 4" while Confirm said "5 of 5", and the main menu's profiles said "1 of 3" while the menu said "of 8". It's all one list now, the way the arrows move through it, and Home reaches the top of it.
- Fixed: I names a warning that pops up over a room, like the Cargo Bay's "Warning" when you switch what it stores, instead of the room behind it. On the Game Over screen it no longer adds the trip you were on.

## Friday October 16th 2026

Version 0.3.28

Team picks, battles, story cards and stories you're parked on.

- Fixed: on an away team or battle slot, leaving the hero list with Escape or Backspace took that hero off the team. The hero stays now.
- Changed: the battle setup tells you when Surrender or Use Cloaking can't be used in this fight, like "Not available: Surrender, Use Cloaking". If you can't surrender, losing can end the game, so it's worth knowing before you start.
- Changed: End in the battle setup goes to Start Combat, the same way it reaches Start Mission on an away team.
- Changed: if you set course for a story point Voyager is already sitting at, it now says the story starts when Voyager arrives, and to fly to another point and back. Before, it just said Voyager was already there and nothing happened.
- Fixed: I on a story card says its Continue button, and in the lines after a card it names who's talking again.

## Friday October 16th 2026

Version 0.3.27

Rooms you couldn't close, events, battles and I.

- Fixed: a room window where nothing can be pressed, like a damaged Aeroshuttle Bay with no free work team, couldn't be closed, and Down on its Trading tab moved you around the ship behind it. Escape closes it now, and the arrows stay in the window.
- Fixed: in an event, Enter sometimes picked the last option, like "Leave for now", even though you'd just heard the first one. Enter picks the option you heard now.
- Fixed: the Enter that starts a battle could open the Orders wheel right away. It waits a moment now.
- Changed: map points with a story waiting say "main mission" or "side mission", like "Debris Field, main mission".
- Changed: I in a conversation says the choice you're on, or who's talking, instead of just "Dialogue". On an away mission result it says "Away mission result" and how it went, and over a room window it names the offer or message in front.

## Friday October 16th 2026

Version 0.3.26

Settings, the main menu and the Cargo Bay.

- Fixed: the Graphics settings counted section titles, empty rows and settings you can't change, so the numbers jumped, like 6 of 18 straight to 9 of 18. They go 1 to 13 now with nothing skipped.
- Fixed: on the main menu, if you went into an empty Q Trial slot you couldn't get back out with the keyboard. Backspace takes you back to the slot now, and it works the same from a campaign profile's Continue Game.
- Fixed: changing what a Cargo Bay stores can make you lose stock, and the game warns you first. The warning said the amount before the sentence, and your arrows stayed in the room behind it. It reads in order now, like "you would lose the following resources: Deuterium -500", and Up and Down move between Continue and Return.

## Friday October 16th 2026

Version 0.3.25

I tells you more about where you are, and a battle setup fix.

- Changed: I now names the event or message you're in. An event says its name, like "Ecosphere Planet", instead of "Point of interest". A mission offer says its title, like "Duranium Reserves. Acknowledged.", instead of "Menu".
- Fixed: in some Q Trials ambushes Surrender and Use Cloak can't be used, and Down from the last hero slot got stuck on Surrender with no way off it. Up and Down skip those now and go straight to Auto Resolve.

## Friday October 16th 2026

Version 0.3.24

Small fixes from playing the campaign further.

- Fixed: Set course to a planet you're already orbiting said "Under way" and then nothing, forever. It tells you now: "Voyager did not move. It may already be at Avery III." And "Arrived" isn't said over the conversation when you get to a big planet anymore.
- Fixed: before a battle, if you pressed Start Combat with an empty slot, the warning came up but your keys went to the screen behind it. You can move through its Return and Continue now.
- Fixed: after adding a work team in the Engineering Office, you couldn't reach the new team with the arrows. New buttons join the list as they appear now, and you stay where you were.
- Fixed: Add work team did nothing when the office already had all the teams it can hold. It says so now.
- Fixed: the Workshop said "2 of 2" when there was only one blueprint.

## Friday October 16th 2026

Version 0.3.23

More battle sounds made into words, trading with the Aeroshuttle, and the hero list in the campaign.

- New: firing a torpedo with Shift says so now, with how many you have left, like "Torpedo fired, 35 left."
- New: an Aeroshuttle trade you've started says "Trade under way, 16 cycles left." When it's finished it says "Trade done", Enter takes you to Collect, and collecting tells you what you got, like "Collected: 4 Dilithium."
- Fixed: in the campaign, the Overview's Heroes tab said "0 heroes" and Up and Down did nothing. It lists all your heroes now, same as in Q Trials.
- Fixed: Back on a page of the battle orders, like Defensive Actions, closed the whole orders menu. It takes you back up one level now.
- Fixed: repair orders in battle say the system's health out of its most, like "Repair Weapons, health 20 of 25."
- Fixed: a room whose repair or building had finished, waiting for you to close the Construction Report, said "repairing, ready." It says "repairing done" now.
- Fixed: trade offers said "04 Dilithium", and one that could be traded said "Not possible" with leftover placeholder text. Both read properly now.
- Changed: I on a crew notice used to give only who sent it, like "Lieutenant Lani." It says what it's about too, like "Lieutenant Lani. Deuterium running low."

## Friday October 16th 2026

Version 0.3.22

Energy in battle, and the build menu without the mouse.

- New: moving energy in battle talks now. Left and Right say which system you picked and how much energy it has, like "Engine 1 of 2, 2 spare", and Up and Down say the new amount. If a system is already full or empty, it tells you that too instead of staying quiet. I in battle includes the energy for all three systems.
- Changed: the build menu used to read a room's description and costs only when the mouse got there. When it doesn't, the mod reads the same thing from the game itself, along with why you can't build it, like "No available work team" or "Missing technology".
- Fixed: an event result could say the same amount twice, like "400 food. 400 food stored." It says "400 food stored." now.
- Fixed: a few rooms had names the game doesn't use. It's Engineering Office, Officers' Quarters, Phaser Control Room and Disruptor Control Room now.

## Friday October 16th 2026

Version 0.3.21

Set course without the mouse.

- Changed: Set course now goes through the game directly first, with no mouse at all, so "Under way" comes right away. The mouse is only tried when the game says the trip isn't possible. If your Set course kept saying "not set", this is the fix.
- Fixed: choosing Surrender before a battle works with Enter, same as the other battle setup buttons.

## Friday October 16th 2026

Version 0.3.20

Building rooms and the installer, checked with JAWS this time, and a fix for a player who couldn't set a course.

- Fixed: for some players, Set course always said "not set". The mod points the mouse at the place and the game picks it up from there, but on some computers the game never did, even with the mouse exactly in the right spot. When that happens now, the mod sets the course through the game directly, without the mouse.
- Fixed: after you chose a room to build, the build menu stayed open behind everything. It could take the arrow keys away from the next window, even the Game Over screen. It closes by itself now and says "Building" and the room's name.
- Fixed: Enter on something in a ship's room menu that the game won't allow, like Clear Debris on a deck with no life support, did nothing and said nothing. It says why now, for example "Not possible: No Life Support".
- Fixed: a Cargo Bay's description in the build menu read "+500 storage capacity" four times without saying which resource. It says "+500 deuterium storage capacity, +500 food storage capacity" and so on now. The same clean-up now runs in the tech tree, Q Trials setup and story text.
- Fixed: if you install Voyager Access before the game, the last page of setup said the mod was "installed and added to the game" and offered to start it. It says the game isn't installed yet and what to do next, with no start box.

## Thursday October 15th 2026

Version 0.3.19

More from going through the ship's rooms one by one.

- New: quarters rooms read who lives there on their Crew Info tab, for example "Inhabitants 12 of 12: Jelan K'Var, injured; Jacob Baker, Science Laboratory; ..." It used to say only "Crew Info tab".
- New: Main Engineering's selected warp core tier says what it makes and burns, for example "Tier 1, selected, makes 120 energy, burns 24 deuterium per cycle".
- New: a cargo bay says how full it is when you open it, for example "Stock 14 percent full".
- Fixed: after loading a save, the objectives came in pieces, one mission and then "New mission" for each of the others, or sometimes not at all. They're read once, all together, a few seconds after the load.
- New: in the full game, a point you scan keeps what was found in the System Map list, like "Shipwreck, Tritanium", instead of just "scanned".
- New: the "Display settings have been changed" question after changing the resolution is read with its Reject and Accept buttons.
- Changed: for players whose Set course says "not set" every time. The helper now handles screens with different display scaling, which may be the cause, and it notes each mouse move in the report you copy with the backtick key, so if it still happens, a new report will show why.

## Thursday October 15th 2026

Version 0.3.18

From a run through the third sector, including a battle screen that wouldn't do what you chose.

- Fixed: before a battle, Enter always started the fight, whatever you were on. Enter on a hero slot now opens the hero list, Enter on Auto Resolve opens Auto Resolve, and Enter on Start Combat starts the battle. Auto Resolve used to leave the game stuck halfway into the fight.
- New: in the orders wheel, an order the game won't let you use in that fight, like Surrender or Flee, says "not available now", and Enter on it tells you so instead of doing nothing.
- Changed: personal logs are read aloud by the game, so the mod only reads the log's title, its tabs and Close.
- Fixed: the first line after you pick a dialogue choice could be read with the wrong speaker's name, for example Janeway for a line that's Tuvok's.
- Fixed: objectives no longer talk during conversations, battles or Q's speeches. They wait until it's over. As a battle began, the main mission was announced as ended when it had only moved to its next objective.
- Fixed: "System map. Nothing selected" was read after "Game Over".
- Fixed: I during a battle added the trip you were on before it.
- Changed: a dialogue choice's chance with a hero bonus is read as "chance 40%, plus 45% bonus" instead of "40% + 45%".
- Fixed: arriving somewhere that starts a conversation said "Arrived" over the conversation's choices.
- New: when the game can't save right now, its message is read.

## Thursday October 15th 2026

Version 0.3.17

From playing the campaign on into its third sector.

- Fixed: at the start of the third sector, a personal log opens over the map with a page for each officer. Only "Close" was read, and while it stayed open Set course didn't work. The log is read now ("Personal Log, Lieutenant Tuvok..."), Left and Right switch between the officers' logs, and Enter on Close closes it.
- Fixed: story cards said "CONTINUE" before their text. The card is read first now, then "Continue".

## Thursday October 15th 2026

Version 0.3.16

More from a second Q Trial, including a reward screen you couldn't get past.

- Fixed: after finishing a Q Trials sector, the reward choice had nothing to select, so Confirm never became available. Each reward is read now, for example "Hero: B'Elanna, rank 1, Klingon - Innovator. Engineering 38, Science 22. Combat ability: Instant Shield Recharge." Enter chooses one and says so, and Confirm is at the end of the list.
- New: Auto Resolve in a battle opens a window that was silent apart from "Proceed". It's read now: "Combat autoresolve. Combat power 95 against 73. Hull 400. Survival chance 100%. Torpedoes added 0 of 7." Add torpedo and Remove torpedo say the new count.
- Fixed: a battle's result came after its "Proceed" button. The result is read first now.
- New: Aeroshuttle trade offers are read, for example "Trade Offer 1. You give 1500 Deuterium. You get 17 Dilithium. Takes 24 cycles. Expires in 14 cycles." Enter on an offer moves to its Trade button, or Dismiss when you can't pay. The arrows couldn't reach either.
- Fixed: a room without life support offered Dismantle and its power switch as if they worked, and Enter did nothing. They say "Not possible: no life support" now, and Enter on any room button that can't be used says why.
- Fixed: salvage results said a resource twice, as in "TRITANIUM +30 tritanium". Now it's "+30 tritanium".
- Fixed: locked event options no longer say "Left and Right choose a hero".

## Thursday October 15th 2026

Version 0.3.15

Rooms and screens from a longer Q Trial, and one of your suggestions.

- Changed: words the game writes run together are split for speech, so "Shuttlebay" is said "Shuttle bay", and the same goes for Sickbay, Holodeck, Turbolift, Aeroshuttle and a few more. Some voices were running them into one word.
- Fixed: the Shuttle bay's Shuttles tab read its only button as "Class 2 Shuttle". That button dismantles the shuttle. It now says "Dismantle Class 2 Shuttle. Returns 40 Duranium, 2 Dilithium."
- New: the Aeroshuttle Bay's Trading tab reads its page, for example "New trade offer in 16 cycles. Awaiting new trade offers, 2 slots." It used to say only "Trading tab".
- New: a Cargo Bay's storage choices name their resource, for example "Duranium, +50 storage, selected". They used to say only "+50".
- Fixed: room upgrade descriptions ran their lists together ("750 DEUTERIUM storage capacity 750 FOOD storage capacity"). They're read with commas now.
- Fixed: the tech tree gave every technology a tier one too high. The starting technologies are called that now, and a technology locked because its tier isn't researched says so.
- New: in the Overview, the Heroes tab is a list. Up and Down choose a hero and read their trait, whether they're recruited, where they are, their bonus or combat ability, and their biography. Before, only the first hero's details could be heard.
- Changed: the Overview's Combat tab reads each room with how many are built and its combat power, then the totals, instead of a jumble of numbers.
- Fixed: the Overview said "uses -24 deuterium", lost the brackets around morale ranges, and repeated itself on the Q Trials tab. Right on the Q Trials tab no longer opens the Q Modifier picker.

## Thursday October 15th 2026

Version 0.3.14

A crash fix for Q Trials, and more from a Q Trial's first battle.

- Fixed: flying to a Trading Station in Q Trials crashed the game, every time. The mod was looking up the station's options the slow way, the way the demo needs, and one of those lookups took the game down. It now asks the game for each option directly, in every event.
- New: Surrender in the battle setup says what it costs, for example "Surrender, 1 of 3. Costs 40 Duranium". The game only shows that while the mouse is over it.
- Fixed: the battle setup named only the first enemy ship. It now names them all, for example "against Kazon Carrier, combat power 61; Kazon Swarm Alpha, combat power 30".
- Fixed: the battle setup said "Choose up to 3 heroes" and offered a third slot the game had hidden, because only two heroes were free. It now counts only the slots you can use.
- Changed: event results no longer say "65% of the possible reward". That number is the game's outcome rate, and it contradicted the option's "Up to" amount. The outcome itself is still said, for example "Outcome: good. 447 deuterium."
- Fixed: after scanning a point that gives an item, the item became a one-line list that took the arrows away from the map, and Backspace said "Nothing to go back to". The item is still read with the scan, and the arrows stay on the map.
- Fixed: a damaged room with only Repair said "Repair, 6 of 6", counting the room's tabs.
- Fixed: Sector Map systems with a settlement said its name twice.

## Thursday October 15th 2026

Version 0.3.13

More fixes from the forum, and from replaying the campaign's start.

- New: away missions explain how to choose. The first time choices come up, you hear "To choose: Down to a hero and press Enter, then Down to Confirm and press Enter." After you pick a hero, they say "Confirm is after the heroes." A forum player was stuck on the cornfield's "Look for any footprints" with a hero already picked.
- New: you also hear that a hero below the skill needed can still succeed, with less chance. At the start of the campaign nobody meets those numbers, and Tom Paris still found the path with Command 25 of 29.
- Fixed: with the pause menu open during an away mission, the arrows moved the pause menu and the mission's choices at the same time. They only move the pause menu now, and I says "Menu".
- Fixed: after loading a different save, your objectives came out as "Done:" followed by the last save's objectives. The new save's objectives are read in full now.
- New: Restart Sector's "Overwrite Savegame" warning is read, with BACK and ACCEPT. It was silent, and the arrows stayed on the menu behind it.
- New: the Game Over screen is read, then its buttons, such as "Return to Main Menu, 1 of 2".
- Fixed: "Team complete: Enter starts the mission" was said with only one hero of three picked. It now waits for every slot.
- Fixed: an event's first option was sometimes read twice in a row.
- Changed: every tutorial with something to press now gives its keys, not just the ones met so far.

## Thursday October 15th 2026

Version 0.3.12

Fixes from your forum reports and from replaying the first mission.

- New: when someone calls the ship, you hear "Incoming call. To answer, press N and choose Incoming calls." The first mission's "Accept Tuvok's COMMS request" is one of these, and nothing used to tell you where to answer it.
- New: menus and room buttons say where you are in them, for example "RESUME, 1 of 5" in the pause menu or "Dismantle, 2 of 3" in a room, so you know when you've heard the whole list.
- Changed: event chances are now the ones the game really uses, room bonuses included. Before, a "60% excellent, 40% bad" option could come out "good", because a room you have was adding a chance the mod didn't know about.
- Fixed: after an optional dialogue choice, the remaining choices came back without a word, and Enter could pick one you hadn't heard. They're read again now.
- Fixed: dialogue choices with a cost read as "Expander 15 10". Now it's "Expander. Costs 15 Duranium, 10 Tritanium."
- New: on an away mission, a hero with the trait a choice asks for says so, for example "Tom Paris, Command 25, 14 needed, enough, has the Pilot trait".
- Changed: tutorials leave out the game's mouse and controller directions, such as "Click on the question mark icon on the left of the screen", and give the keys instead. Two more tutorials have keys: Replicator Food and Build Rooms.
- New: Sickbay's Manage Patients tab reads each patient, what's wrong and how many cycles until they recover.
- New: the Bridge's Combat Allies tab reads the ally, its combat power, what recruiting costs and the upkeep each cycle. It used to be a string of loose numbers.
- New: the Workshop says when there are no blueprints to craft.
- Fixed: Delete Profile in the main menu only got selected on Enter. It now opens its warning, which is read, with BACK and ACCEPT.

## Thursday October 15th 2026

Version 0.3.11

More fixes from the full game's second sector, State of Flux.

- Changed: when your objectives change, you hear only what changed, for example "Done: Assign Neelix to the Mess Hall" or "New mission: Final Warning, 50 cycles left". The whole list is still read when a game loads, and O reads it any time.
- Fixed: Backspace in a room's hero list took the hero out of the room. The room now keeps its hero. The game's own Escape still empties the slot, so use Backspace.
- New: a room's assigned hero says what the hero adds, for example "Assigned hero: Neelix. +4 MORALE per CYCLE", and the hero list says "2 of 3".
- New: C says how much of each resource the ship can store, for example "Duranium 100, max 100". Events kept saying "storage full" with no way to know the limit.
- New: a point on the System Map with a side mission says so, for example "Planetoid, side mission".
- Changed: systems on the Sector Map have the names the game shows when you point at them, said the Starfleet way: "System 3 5 2 oh point 1" instead of "Star system" for all four. The number after the point is kept now, because the systems in a sector can differ only there.
- Fixed: after a story scene, Set course to a far planet failed twice and said so. The game keeps the camera on Voyager then, and the planet was off the screen. Voyager Access now zooms the map out until the planet is on screen.
- Fixed: after you chose an event option, "CONTINUE" was sometimes said before the result, and the event's opening text could be read a second time. Now you hear the result, then CONTINUE.
- Fixed: a side mission offer said its first answer before its message. The answers also say "1 of 2" now.
- Fixed: the ring on a ruined room only said "Clear Debris". It now reads what the game shows, for example "Clearing this ruin will give you some resources back. Gives 16 duranium."
- Fixed: closing one of Voyager Access's lists with Escape also said "RESUME" from the pause menu the same key opened.
- Fixed: the first-launch Performance Selection screen could say "CONFIRM" before its message.
- Fixed: two wording slips. An event option ended in "exposure:." and a choice said "Level 1- Chance".

## Thursday October 15th 2026

Version 0.3.10

Less repeating.

- Fixed: the objective was read again every cycle while a number in it changed, such as "Store Deuterium (552 of 900)" going down as fuel burns. It now comes up only when the goals themselves change. O still reads the current numbers.
- Fixed: after a report such as the Construction Report, its first button, for example "CLOSE, 1 of 1", was said twice.
- Fixed: opening the Mess Hall could say "Button, 1 of 1" before its real first button.

## Thursday October 15th 2026

Version 0.3.9

Smaller fixes found while replaying the demo and the full game.

- Fixed: opening a room said its first button, then the room, then the button again. Now you hear the room, then the button, once each.
- Fixed: Backspace in a list of heroes, either a room's "Assign a hero" list or the away team's, said "Nothing to go back to". It now closes the list and puts you back where you were.
- New: Home and End on the away team screen go to the first slot and to Start Mission.
- Changed: I names the window you're in, for example "Construction Report. CLOSE, 1 of 2" or "Away team", and says "Menu" in the pause menu instead of naming the room behind it.
- Fixed: while a report was open, I, N and V worked on the map behind it. N now stays closed there, and V says "Close the window first".

## Thursday October 15th 2026

Version 0.3.8

Fixes from the full game's second sector, State of Flux.

- Changed: places on the System Map now use the game's own names, the same ones a sighted player sees when pointing at them. You'll hear "Vidiian Interceptor" or "Kazon Carrier" instead of just "Ship", and the story planet is "Class L Planet with Potential Food Sources" instead of a long made-up name.
- Changed: O and new objectives name each mission with its own goals, for example "State of Flux: Visit the Class L Planet. Quarters Crisis, 37 cycles left: Build 2 new Crew Quarters". Before, side mission goals were read as if they belonged to the main story.
- Fixed: the objective is no longer read again every cycle just because a side mission's countdown went down.
- Fixed: the Energy loss report was read in bits ("Phaser. Control. Room"). It now says what happened, the energy before and after, and which rooms were switched off and how much energy each one used.
- Fixed: the Research Report now says what you got, for example "Rewards: 100 Food. New craftable item: Apples & Roots", and isn't read twice.
- Fixed: pressing I while the N list is open names the item you're on instead of the map behind the list.

## Wednesday October 14th 2026

Version 0.3.7

Fixes from playing the full game's campaign from the start.

- Fixed: Set course could do nothing when Voyager was sitting right on top of the place you wanted, or when the camera didn't move to it. The campaign got stuck at "Fly back to Ocampa". Set course now aims at the place itself.
- Fixed: incoming calls were read as nothing at all since 0.3.4. They now say who's calling, for example "Incoming call: Caretaker".
- Fixed: the Caretaker's choices on the bridge didn't move with Up and Down, and Enter could press the wrong part of a choice.
- Fixed: on an away mission, Enter could send a different hero than the one you heard, because the game was still looking at another hero. It now picks the hero you're on. Confirm names everyone you chose, and Enter on a hero you already chose just says so.
- Fixed: on the away team screen, Enter right after choosing a hero could start the mission by accident.
- New: away mission choices say their trait, for example "Trait: Ocampa".
- New: in the battle setup, heroes who can't join this battle say "unavailable". Before, Enter on them did nothing and nothing said why.
- Fixed: the battle result listed rewards as if they were injuries ("Injuries: None, Gained, Morale, 50"). It now says "Injuries: none. Gained: 50 Morale", and long lists start with how many there are, for example "Injuries, 22".
- New: the Q Trials results screen at the end of a sector or a trial is read: performance, distance and rewards.
- New: starting an analysis in the Science Laboratory says "Analysis started".
- New: I in the tech tree says the category and the item you're on.

## Wednesday October 14th 2026

Version 0.3.6

"Where am I" has moved from L to I.

- Changed: I now says where you are and what's selected, and in battle it reads both ships. L used to do this, but in Q Trials the game itself opens Leave Sector when you press L, so one press did both. Leave sector is still in the N list.
- Fixed: the battle setup's "You still have unassigned slots" warning could be read as just "Return", without the warning.
- Fixed: "Halfway to" and "Arrived at" were still said over the battle setup when a battle interrupted your trip.

## Wednesday October 14th 2026

Version 0.3.5

Q Trials can now be played past the start, and the full game's DLC page and battles read properly.

- Fixed: moving through an event's options could crash the game or stop Voyager Access. It happened most at a Repair Station in Q Trials.
- New: in Q Trials, many event options can take a hero. Left and Right choose one, for example "Joe Carey, Engineering 33, 4 of 6", or No hero, and Enter carries the option out with them. Each option says which skill it tests.
- New: options you can't afford, like a trade without enough Tritanium, are read as locked and say what's missing, for example "Not enough Tritanium". Before, they were skipped without a word.
- New: Leave Sector is read. You hear how far you are from home, then each sector with its distance, its cost and whether it's locked. Enter on a locked sector says why. In Q Trials, Leave sector is also in the N list.
- New: an event's result now reads what happened to your ship and crew, like "FOOD +200" or "5 CREW got Severely injured".
- Fixed: scanning a second planet while the first one's details were still showing read nothing about the new planet, only its rewards as a list. A scan also no longer says "nothing found" when the planet has resources, and system names like "112 Vidiian System" are read properly.
- Fixed: side mission offers with an option you can't take never read their message.
- Fixed: in full game battles, the combat goal is read again (O, and when the battle starts), and pausing and resuming is announced. Shields and attacks are named bow, aft, port and starboard instead of Right and Left.
- Fixed: "Halfway to" and "Arrived at" are no longer said over a battle that interrupts your trip.
- New: on the Q Trials setup, choosing a captain, a Q Modifier or a Q Challenges level says what you chose. A full team says so instead of just "not chosen", and Start Game says when it isn't available yet. Down now reaches it.
- Fixed: Backspace in a Q Trials list threw you back to the main menu and lost your setup. It now closes the list.
- Fixed: after Start Game, the Q Trials setup was read over the loading screen and the trial itself.
- Changed: Q's opening speech and the campaign's opening narration are voiced, so Voyager Access no longer reads them over the audio. R still repeats the last line.
- Fixed: Voyager herself was listed as a point on the Q Trials map, and stations had names like "CustomPOILocation RepairStation". They're now Repair station and Trading station.
- New: Enter on a DLC tile in the main menu reads the whole card: its description, and its new missions, heroes and technologies. Backspace closes the DLC panel.
- Fixed: Up and Down on the full game's main menu wandered into the Campaign and Q Trials profiles and the DLC tiles.
- Fixed: Backspace now closes the Credits, as Escape does.
- Fixed: in away missions, Confirm names every hero you chose, not just the last one.
- Fixed: windows read their message before their buttons. "System map" is no longer read over the Exit to Main Menu confirmation, over the room list, or while you move through the map.
- Fixed: the Warp Core tutorial named the wrong tab for the full game, and "already scanned: scanned" is now just "already scanned".

## Wednesday October 14th 2026

Version 0.3.4

Q Trials can now be set up and started from the keyboard.

- New: the Q Trials setup screen is read. When it opens you hear the ship and its numbers (difficulty, decks, building space, hull, hero slots, crew); Left and Right change ship. Up and Down move through the captain, the eight hero slots, the Q Modifier, the Q Challenges level and Start Game, each with where it is in the list.
- New: Enter on the captain, a hero slot, the Q Modifier or the Q Challenges opens its list of choices, also read as a list. Captains and heroes say their trait, bonus, skills and ability; Q Modifiers and Q Challenges levels say what they do, and whether they are locked or selected.
- New: in the hero list, Enter chooses or removes a hero and says how many you have, for example "Tom Paris chosen, 2 of 8". Your captain is named as not available. Confirm says how many are chosen and closes the list.
- New: Start Game on the Q Trials setup is held down for you, and Q's narration at the start of a trial is read a line at a time.
- New: F1 explains the keys on the difficulty window and the Q Trials setup, and L names them.
- Fixed: a hero with two skills could be read with a third skill left over from the hero before, for example Harry Kim with Janeway's "Science 22".

## Wednesday October 14th 2026

Version 0.3.3

You can now start a campaign in the full game, choose its difficulty, and set up a Custom game.

- Fixed: in the full game, Enter on CAMPAIGN or Q TRIALS did nothing, so a new game could not be started from the keyboard. Enter now opens the three profiles, and Enter on a profile takes you to NEW CAMPAIGN (or NEW Q TRIAL).
- New: the difficulty window is read as a list. Each mode says its name, where it is in the list, its description and its points, for example "Survival, 3 of 4. The authentic Delta Quadrant experience... Resources are limited. Combat is challenging." Enter on a mode starts the game.
- New: Custom Difficulty Settings is one list too: the Adventure, Survival and Years of Hell presets, then every setting with its section, value and description ("Saving. Challenge Mode, Disabled, 4 of 19. Disables manual saving..."), then Start Game. Left and Right change a setting and say the new value. Home and End go to the top and bottom. Escape goes back to the modes.
- New: buttons the game wants held down, like Custom's Start Game, are held for you when you press Enter. You hear "Holding".
- New: the loading screen's text is read ("You are the Captain of the Federation starship U.S.S. Voyager..."). This works in the demo too.
- New: the full game's opening narration is read a line at a time. Shift+Enter skips it, R repeats the last line, and F1 says so. The System Map is no longer announced over the top of it.
- Fixed: in the pause menu during a conversation, Enter on a button (MAIN MENU, for example) moved the conversation on instead of pressing the button.
- New: "Exit to Main Menu. Are you sure? You will lose all progress since the game was last saved" is now read, with BACK and ACCEPT as a list. BACK comes first, so pressing Enter twice by accident does not throw away your progress.
- New: Q Trials has a start. Its warning is read, with ABORT and ACCEPT as a list. The Q Trials setup screen after it is not read yet; Voyager Access says so, and Escape goes back. Reading that screen is the next job.
- Fixed: after a window like that warning opened, focus could be put back on the main menu behind it, where the arrows and Enter worked on buttons you could not see.

## Wednesday October 14th 2026

Version 0.3.2

Voyager Access now works with the full game, not just the demo.

- Fixed: with the full game installed, the installer said the game was not there, and nothing was spoken in the game. The full game's program has a different name from the demo's, and Voyager Access only knew the demo's. If this happened to you, download and run the installer once more; it finds the full game, and updates come in by themselves after that.
- Changed: if you have both the demo and the full game, Voyager Access is added to both.
- Changed: "Add Voyager Access to the game" in the Start menu now starts the game when it is done, instead of showing a message telling you to.
- Fixed: the full game's main menu said "0LY" after every item. That text is hidden on screen, and it is no longer read.
- Fixed: the DLC tiles on the main menu read their small badges ("Dx", "1, 2, 3, 4") before their names. They now say just the name, plus "Visit Store Page" for DLC you don't own.
- Fixed: arrowing in Settings or the main menu could move into hidden menus behind them. Down now stops on the last setting of each tab, and on EXIT at the end of the main menu, and Up and Down never move between the main menu and Settings.
- Fixed: Backspace on a Settings tab could say "Nothing to go back to" and leave you in Settings. It now goes back to SETTINGS on the main menu.
- Fixed: the graphics quality and Gamma screens shown the first time the game starts now read their message first ("Choose a graphics quality that matches your hardware performance"), instead of after the list of buttons.

## Wednesday October 14th 2026

Version 0.3.1

- Fixed: an update found just after the game started could close the game wherever you were, even if you had already loaded a save. Now it only does that while you are at the main menu. Otherwise it waits for you to close the game, or for F12.
- Fixed: if you installed Voyager Access before the game, the installer said it would add itself to the game later by itself. It doesn't, so it now tells you what to do: once the game is installed, choose "Add Voyager Access to the game" from the Voyager Access folder in the Start menu, or run the installer again.
- New: the instructions now start with a Getting started section: Steam, then the game or its free demo, then Voyager Access.

## Wednesday October 14th 2026

Version 0.3.0

The whole demo can now be played to the end, including the battles.

- New: Control F1 lists every key, grouped by screen. Up and Down move, Home and End go to the ends, Escape or Backspace close it. F1 still says the keys for the screen you are on.
- New: battles. Before a battle you hear both ships' combat power, and the hero list says each hero's ability. In battle, Enter opens Orders, and the order wheel is a list, including the enemy's systems with their health. L reads both ships, the enemies, your order, torpedoes, abilities and the goal. Target changes (Tab), abilities becoming active or ready, and pauses are spoken as they happen. The result says victory or defeat, hull, injuries and damaged rooms.
- New: building rooms. In the construction ring, each room says how wide it is and whether it fits at the space you chose. Enter builds it there, or says why it cannot (not enough room, resources or work teams).
- New: the tech tree is a list of tiers and technologies. Left and Right switch category. Enter opens an item, which reads its cost and description, and Enter again begins the research.
- New: side mission requests read their title, who asks, what they want and the time limit, then the choices. Choices you cannot take are named.
- New: C starts with hull integrity.
- New: room windows say how much energy the room uses. If the game will not switch a room on, you hear why ("Did not switch. Energy 60, rooms use 60"). A warp core tier that will not engage says so too.
- New: the Workshop's blueprints and crafting are read like research.
- New: major decisions, such as what to do with the Array, say "Major decision". The game wants them held down; Enter holds them for you.
- Changed: Escape also closes the mod's lists (C, J, N, the key list), without leaving the pause menu open.
- Fixed: Enter pressed just as dialogue choices appear no longer picks the first one before you hear it. It reads the choice instead.
- Fixed: away missions. The hero list says "3 of 6" and who is already on the team, and stops at its ends. The mission summary is read once, when it has finished counting. Results say "Skill 28, 25 needed".
- Fixed: Home and End work on dialogue choices.
- Fixed: smaller wording fixes, such as "1 cycle", Dismantle saying "Returns" instead of "Costs", and Set course saying when Voyager is already there.

## Sunday October 11th 2026

Version 0.2.7

A tidier installer.

- Changed: installing shows one window at the end instead of two. The setup's last page says Voyager Access is ready, and the extra OK box is gone.
- New: that last page has a "Start Star Trek: Voyager - Across the Unknown" checkbox, already checked, so pressing Finish starts the game.
- Changed: the installer no longer mentions the demo. It works the same for the demo and the full game.

## Sunday October 11th 2026

Version 0.2.6

- Fixed: on some computers an update was found, the game closed, and then nothing happened: the update never installed and the game never came back, and the same thing repeated at every start. The installer is now started so that Steam cannot stop it part way. If you are stuck like this, download the installer from the link in the README once and run it; updates work by themselves after that.
- New: each update's installer keeps a log, and the troubleshooting report (backtick) includes it, so a failed update can be explained.

## Sunday October 11th 2026

Version 0.2.5

- New: Ctrl+F12 lists what is new in Voyager Access, one item at a time, like the status list on C. Up and Down move; Ctrl+F12, Backspace or Enter close it. After an update, you hear that Ctrl+F12 is there.
- Fixed: after switching away from the game and back, a menu could be left with nothing selected, so the arrows did nothing. The last item you were on is selected again.
- Fixed: with the status list or What's new open over a menu, the arrows also moved the menu behind it, and the two talked over each other. Only the list moves now.

## Sunday October 11th 2026

Version 0.2.4

This one is about getting around: the game's navigation buttons, your status, and a few windows that would not let you do anything.

- New: N lists the game's navigation buttons, such as Ship, System and Overview. Up and Down choose, Enter presses, Backspace closes the list. More buttons appear in the list as the story unlocks them, and it works in the ship view and on the System Map.
- New: C now opens your status as a list instead of reading it all in one breath. Up and Down move through resources, crew, work teams, fuel, energy, battery and morale, one item at a time. C, Backspace or Enter close it.
- New: the Overview is read in order, and Left and Right switch between its Warp Core, Morale, Crew, Heroes and Combat tabs.
- New: after Set course, you hear "Arrived at" the point once Voyager gets there. Before, Voyager just stopped quietly, which made it easy to think the course never took.
- Fixed: the Construction Report, which comes up when a repair or build finishes, was read in a jumbled order, with numbers that had no labels. It now reads the rooms under Repaired, Built or Dismantled, then the totals, then what its two buttons do.
- Fixed: some windows, the Construction Report among them, opened with nothing selected, so Enter did nothing and you were stuck. Up, Down and Enter now work in them.
- New: tutorials end with the keys to use in Voyager Access, since the game's own text talks about clicking and looking.
- New: backtick, the key to the left of 1, copies a troubleshooting report to your clipboard, so you can paste it into a message when something goes wrong.

## Sunday October 11th 2026

Version 0.2.3

- New: resuming a game, closing a room or a dialogue, and switching views with V all tell you where you are: the ship view or the System Map, and the room or point you are on.
- Fixed: a stray "1" was spoken when the System Map opened.

## Sunday October 11th 2026

Version 0.2.2

- Changed: installing or updating no longer asks you anything. Steam closes for a moment and starts again by itself to set the game's launch options. If you are playing another game through Steam at that moment, Voyager Access waits for it to close instead of cutting it off.

## Sunday October 11th 2026

Version 0.2.1

Voyager Access now starts with the game instead of with Windows.

- Changed: Steam starts Voyager Access when you start the game, and it closes when the game closes. Nothing of it runs when you are not playing.
- Changed: before the game starts, Voyager Access puts itself back if a game update removed it.
- Fixed: "Voyager Access loaded" was sometimes missed when the game started.
- Changed: uninstalling puts the game's launch options in Steam back the way they were.

## Sunday October 11th 2026

Version 0.2.0

- New: rooms say on or off as you move through the decks, life support included. A room's power button says "Life Support on" or "Life Support off", and tells you the new state after you press Enter. Before, pressing it made a sound and nothing else.
- New: L tells you where you are and what is selected.
- Changed: F1 gives only the keys for the screen you are on, instead of adding the general keys every time.
- New: the first room you open says once that Escape closes it, and leaving a room tells you where you are.
- Changed: an update found while you play no longer reloads Voyager Access in the middle of the game, because that could freeze the game. You hear that it is ready, and it installs when you press F12 or close the game.

## Sunday October 11th 2026

Version 0.1.9

Away missions are playable.

- New: the mission's story is read.
- New: Up and Down walk each challenge: what each choice needs, each hero's skill against it, and Confirm. Enter on a hero selects them, and Enter on Confirm confirms. The game itself has no keyboard controls on this screen.
- New: results are read: success or failure, what happened, the reward, and who is now fatigued.
- New: the end of the mission is read: the experience earned and each hero's new rank.

## Sunday October 11th 2026

Version 0.1.8

- Changed: "Press F1 for help" is no longer said on every new screen. It kept coming back after every update. F1 still tells you the keys for the screen you are on.

## Sunday October 11th 2026

Version 0.1.7

- Fixed: Up and Down on the away team screen skipped items and paused for a moment. They now move one item at a time, in order.

## Sunday October 11th 2026

Version 0.1.6

- Fixed: Up and Down did nothing in the away team's hero list; only Left and Right worked.

## Sunday October 11th 2026

Version 0.1.5

- Fixed: Up and Down could skip an item in ordinary lists, a side effect of the change in 0.1.3. They are now left to the game everywhere except rows of buttons.
- New: if Set course does not get Voyager moving, you hear that the course was not set, so you can choose it again.

## Sunday October 11th 2026

Version 0.1.4

- New: F12 checks for an update whenever you press it. You hear "up to date", or that an update is ready; press F12 again to restart the game and install it. One press never closes the game.

## Sunday October 11th 2026

Version 0.1.3

- New: the away team screen is read. Each slot says which hero is in it or that it is empty, the hero list names each hero's skills, and the mission is described when the screen opens.
- Changed: Up and Down move through every screen, whatever its layout. A screen reader user cannot tell whether buttons sit side by side or one above another, so a row of buttons is a list too.
- Changed: event choices start with a one-word verdict and say what each number means: "Good: 70% chance of a good outcome, 30% chance of a bad outcome."

## Sunday October 11th 2026

Version 0.1.2

- New: updates reach you while you play. Voyager Access checks when the game starts and every 10 minutes while it runs. The game is never closed for an update unless you press F12, because it only saves at story points.

## Sunday October 11th 2026

Version 0.1.1

- Fixed: the game's one-time Performance Selection and Gamma screens, shown the first time it starts, are now read aloud, and Enter works on them. The Gamma screen opened with nothing selected, so Enter did nothing.

## Sunday October 11th 2026

Version 0.1.0

The first release. The opening of the free Steam demo has been played through with NVDA.

- Menus and settings, dialogue and choices, tutorials, your objective (O), your resources (C), the ship's decks and rooms, room windows with their costs, the System Map with scan results, and point of interest events with their chances are all read.
- F1 gives the keys for whatever screen you are on.

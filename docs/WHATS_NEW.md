# New in Voyager Access

## Saturday October 24th 2026

Version 0.3.81

- Fixed: when a crew report came in just as Voyager arrived somewhere, the place's own event sometimes never opened, and you heard nothing about it. Now you hear "The event at ... did not start. Set course to another point and back to start it." I met this at an abandoned Borg cube, and going away and coming back did start it.
- Fixed: a window with only one button, like the Final Warning card, said nothing when you pressed Up, Down, Home or End. Now it says the button again.
- Changed: F1 now mentions N, the list of places to go, in the ship view and on the System Map.
- Changed: Shift+Enter on a story card, like "Into the Badlands", used to show the same card again and read it all over. Now it tells you Enter continues.

## Friday October 23rd 2026

Version 0.3.80

- Quicker arrivals: when you set course, "Halfway" and "Arrived" now come from the game's own travel signals. You hear "Arrived" about a second after Voyager stops, where it used to take two or three, and I's "percent of the way" is the game's own number now. When the place you reach has an event, you still just hear the event. Thanks to firefly82 for pointing the way!

## Friday October 23rd 2026

Version 0.3.79

These changes come from firefly82's review and the choices I made about it. The idea behind all of them: let the game do what the game does, and tell you what it did.

- Changed: tutorials stay open until you press Enter, so you can hear them again with R, the way a sighted player can read them again. If you press an arrow key while one is open, you'll hear "Tutorial open. Enter closes it, R repeats it."
- Changed: Escape belongs to the game now. It opens the pause menu wherever the game does, even with one of Voyager Access's lists open. Use Backspace to close those lists without the pause menu.
- Changed: when you close a hero list without picking anyone, the game takes that hero out, and the mod used to quietly put them back. Now it tells you what happened, like "Chakotay removed", and you choose.
- Changed: event chances no longer start with "Good", "Mixed" or "Bad". The game's bar has no word on it, and the percentages already tell you.
- Changed: when an arrival event doesn't start, you hear "The event at ... did not start. Set course to another point and back to start it." The old message guessed at a reason the game never gives.
- Faster battles: pausing with Space, picking a target with Tab and the hull milestones are said the moment the game reacts. Tab also says your target when it stays the same, which used to be silent.

## Friday October 23rd 2026

Version 0.3.78

- Faster events: when an event opens, you hear its options and their chances right away. The mod used to slide the mouse down the options for a few seconds to make the game show its numbers, and you heard nothing while it did. Now it just asks the game. Thanks again to firefly82, who found the way!
- After you load a save, you hear where you are as soon as the game's done loading, instead of the mod checking every second until the loading screen goes.

## Friday October 23rd 2026

Version 0.3.77

- Fixed: a few conversation lines never move on with Enter, like Zilis's "Whoops! That probably caused a few new scratches" in the Equinox chase. The mod is supposed to tell you after a few tries that Shift+Enter skips ahead, but right after a choice it stayed quiet, and you could press Enter forever. You hear the tip again now.

## Friday October 23rd 2026

Version 0.3.76

- Fixed: 0.3.75 brought back an old annoyance in conversations. When a new set of choices came up, you could hear the second choice first and then the first one. Now you only hear the choice the game puts you on.
- Fixed: "Voyager is already at" comes from where the ship itself says it is, so a point right beside the one you're at no longer counts as "already there".

## Friday October 23rd 2026

Version 0.3.75

- Fixed: repairing, clearing debris, upgrading or demolishing a room from the ship view never worked, because the game only takes those keys when you hold them down. Rooms now say "Hold E: Repair", "Hold F: Upgrade" or "Hold T: Demolish", and holding the key for about a second does it. Switching power with E is still a quick tap.
- Fixed: the away team's "You still have unassigned slots" warning had gone silent in 0.3.74, so Enter on Start mission seemed to do nothing. You hear the warning again, then Return and Continue.
- Smoother battles: twice a second the mod searched every piece of text in the game just to find out whether the battle was paused, a stutter big enough to swallow a quick key press. It reads the pause from the battle screen itself now, and the unassigned slots warning the same way on every screen. firefly82 measured this one, thank you!
- Fixed: Wait One Cycle, the away mission's Confirm and major dialogue choices are held as long as the game asks, about half a second, instead of two and a half.
- Fixed: a room you can't build in the build ring was read twice, once with the mod's reason and once with the game's, and in German the two even used different words. You hear the room, then the game's reason, once.
- Fixed: the research panel says "Locked" when a technology is locked, puts the technology's name first in every language (in German it started with "Forschung"), and calls an unrevealed one "Unknown technology" instead of question marks.
- Fixed: names with letters like ä, é or Cyrillic letters aren't broken in two anymore, in battles and objectives. "Kazon-Aufklärer" used to come out with a capital R in the middle.
- Fixed: a map point that holds two resources names both, the way the scan does, and resources are named in the game's language, so a German game says "Nahrung" instead of "Food".
- Fixed: "ready in 1 second" in the battle's ability list was English in other languages.

## Thursday October 22nd 2026

Version 0.3.74

- Fixed: when a conversation offered a new set of choices, you sometimes heard the second choice first and then the first one, because the old choice's spot was read before the game moved to the new list. Now you hear the choice the game actually puts you on.
- Fixed: the away team's "You still have unassigned slots" warning keeps Up and Down to its own Return and Continue. Before, Up went to Start mission behind it, and the count said "5 of 6".
- Fixed: an objective that changed during a conversation, a battle or a cutscene is now said once it's over. Before, you could only find out by pressing O.

## Thursday October 22nd 2026

Version 0.3.73

- New: in a battle you now hear what the bars show without pressing I. Each ship's hull is said as it drops past 75, 50, 25 and 10 percent, like "Kazon Carrier, hull 50%", and when the enemy's shield on one side is gone you hear "Kazon Carrier, shield down: port". The game already tells you about your own shields.
- Fixed: opening Gamma from the pause menu during a conversation left the arrows silent, and Enter went on with the conversation behind it. Darker, Brighter and Confirm work there now.
- Fixed: switching the Holodeck off, or its deck's Life Support, during the Dark Frontier training said "Done: Wait until the crew completes their simulation training". It wasn't done, so you now hear "On hold" with the goal that came back, and "Done" once the Holodeck is running again.
- Fixed: switching a deck's Life Support on or off no longer reads out every ruined room and empty space on that deck.

## Thursday October 22nd 2026

Version 0.3.72

- Fixed: in Q Trials, Leave Sector now takes you to the sector you heard and held Enter on. If you moved up and down the list first, the game could still have the other sector picked, and Voyager went there instead.
- Fixed: after Auto Resolve, the battle's result is read as soon as it comes up. It used to wait silently until you pressed a key. Auto Resolve's own Proceed is no longer said again between the result and the result's Proceed.
- Fixed: a room that's switched off on a deck whose life support is down now says "off, no life support", the way the game's info panel shows it. Before, it only said "off", and E does nothing there.
- Fixed: the DLC list on the main menu counts its six cards as six, and End takes you to the last one. It used to say "1 of 7" and End went back to the first card.
- Fixed: a point's details say the system number with its point, like "in system 2 2 oh 8 point 1". The point went missing there, so 2,208.1 came out "2 2 oh 8 1".

## Thursday October 22nd 2026

Version 0.3.71

- Fixed: when a battle ends by itself, its result is read right away. You used to hear nothing until you pressed a key. The result now comes once, before Proceed.
- Fixed: "System map. Nothing selected" no longer comes between the battle tutorial and "Prepare for combat", and the battle setup says "Prepare for combat" before the slot you're on, not around it. "Combat resumed" isn't said while the Orders wheel is open.
- Changed: dialogue choices answer Up and Down a lot quicker, in about a tenth to a third of a second instead of nearly three quarters. At either end of the list you hear the end choice again.
- Fixed: a call or conversation sometimes left the speaker's name off the first line, like Harry Kim's hail, even though the name was on screen.
- New: points on the System Map say the storm, field or cloud they lie in, like "inside Ion Storm". The C list counts the homeless Ex-Borg.
- Fixed: a short hop to the point next door now ends with "Arrived at", and Set course to a point beside Voyager no longer says Voyager is already there. When Voyager really is there, you hear only that, not "Setting course" first.
- Changed: an away mission's header says the system number digit by digit, the Starfleet way, like "system 4 8 3 2 point 1".
- Fixed: in the demo, room changes like "Science Laboratory, off" were silent; you hear them again. Repairing from a room window is said once, and costs say "bio-neural gel packs" when there's more than one.
- New: F1 in the tech tree and the Overview tells you their own keys, and Escape right after opening the tech tree closes it.
- Fixed: a second story card in the same window, like the second Seeking Sanctuary card, is read now.

From firefly82's review this week:

- Changed: a room window is read on the tab you actually see. The Mess Hall opens on its rations, so you no longer hear the description of a tab that isn't showing. Escape from a room says "Ship view" again; sometimes it said nothing.
- New: the ship view tells you every action a room offers, each with its own key, like "E: Toggle power. F: Upgrade. T: Dismantle". An empty space says "Enter: Build room", since E doesn't build.
- Fixed: closing a card like "Overwrite save" or "Return to main menu" is noticed at once, and E after a Construction Report acts on the room again.
- Changed: the main menu, Settings tabs and Restart Sector answer without the small waits they had, and the tech tree's list updates the moment a research starts or stops.

Thanks to firefly82 for another careful package.

## Wednesday October 21st 2026

Version 0.3.70

- Changed: windows, rooms and the Overview are read a lot sooner, and the mod holds the game up far less while it reads them. It used to search every piece of text in the game to read one window; now it reads only that window. The Overview's tabs come up in about a quarter of a second instead of more than half, and you'll hear the ship view sooner after you close a room.
- Fixed: a window right after loading a save, like a personal log, was sometimes never read at all. The mod kept a list of windows it had already read and mixed it up with windows from your last game.
- Fixed: after the game showed its graphics quality screen on first start, the ship view and the System Map were never announced for the rest of that game.
- Fixed: closing an info card, like a Sensor Alert or a crew log, now tells you where you are again.
- Fixed: the first time you open a room, you now hear its description too, not just its name and state.
- Fixed: in an event, the option you're on is said once, with the game's own chances, instead of twice with two different sets of numbers.
- Fixed: in an event where the game has dropped its hero, Left and Right now include No hero again, and every choice says its chances.
- Fixed: on the Overview's Q Trials tab you hear the tab's name first, and Up and Down move through the challenge levels without reading a second list over them. The Overview also no longer says "System map" between tabs, and closing it tells you where you are.
- Fixed: starting or stopping a research no longer reads the whole tier line over the details.
- Fixed: the build ring now reads the ring's own text first and then the part you're on, once.
- Fixed: scanning a second point whose details match the first one's, like two asteroids, now reads the details again.

## Wednesday October 21st 2026

Version 0.3.69

- Fixed: E right after you close a room window now acts on that room. The mod presses the window's buttons with the mouse, so the pointer was left where the last button was, and E could do nothing or hit the wrong room. The pointer now goes back to the room you heard.
- Fixed: after loading a save, the view you land in is announced again once the loading screen is gone.
- Fixed: arriving in a new sector no longer says "System map. Nothing selected" twice, leaving to the main menu no longer says "System map" on the way out, and a dilemma's result no longer gets "System map" read in the middle of it.
- Fixed: pressing I during an away mission's opening story no longer says an empty "Away mission result".
- Changed: Voyager Access now checks its own keys separately from speech, so a key like I, O or C that you press while something is being read is picked up without waiting.
- Changed: in other languages, lines you hear often are translated once and remembered, which takes a little load off the game.

Thanks again to firefly82, whose ideas for making the mod quicker are behind the last two.

## Wednesday October 21st 2026

Version 0.3.68

- Fixed: quick key presses, like a fast E on a room, no longer get lost. The mod used to check the game on a timer, and those checks held the game up just long enough to swallow a short tap. It now listens to the game's own events instead, so the game stays responsive and you hear things sooner. Moving around the System Map is quicker too.
- Fixed: in an event, Down no longer jumps back to the first option while the chances are being worked out. Thanks to TheRev for reporting it.
- New: the room view now tells you what E does on a room and what it costs, like "E: Repair, 6 Duranium, 3 Tritanium".
- New: the C list now includes your torpedoes and how many cycles have passed, and the morale line says how many crew are sick, injured, hungry or homeless, as the screen shows beside the morale bar.
- New: a room or the Ship button on the navigation bar now says when a mission marker is showing on it, like "side mission 10" on the Bridge.
- New: O now says how many cycles a mission has left, like "Deuterium running low, 15 cycles left".
- New: an event option where the game has dropped its hero (a tired hero was taken off) now lets you pick from the heroes who can still go with Left and Right, and Enter sends the team with the one you chose, just like clicking their portrait.
- New: Ctrl+F11 turns on an input log for troubleshooting. It writes the keys you press in the game into the mod's log so we can tell a lost key from one that never got pressed. It's off unless you turn it on, and apart from E, F, T and the mod's own keys, the letters you type are only logged as "a character key".
- Fixed: in Q Trials, Leave Sector now lets you reach Stay for now with Down when only one sector is offered.
- Fixed: after loading a save, or moving to the next sector in Q Trials, your objectives are read as a whole list again. Before, you could hear "Missions ended" for the old sector's goals, or nothing at all.
- Fixed: a room window you open a second time now reads the room's name and details instead of just "Room".
- Fixed: a conversation line that comes back later, like the Doctor's warning in Medical Ethics, is spoken again instead of waiting silently for Enter. The "This line does not move on with Enter" hint also stopped coming up when you'd picked a choice or another window was open.
- Fixed: a dialogue choice with several requirements now reads all of them, so you hear the one you're missing.
- Fixed: a tall room without life support on several decks now says "on decks 4, 5 and 6", in your language.
- Fixed: the System Map no longer says an event "did not open because another window was up" when nothing was open.
- Fixed: the game's own words keep their capital letters in other languages, so German nouns stay capitalized. System numbers in other languages now use the right word for the decimal point.

A big thank you to firefly82, who measured why keys were getting lost and rebuilt much of the mod around the game's own events.

## Tuesday October 20th 2026

Version 0.3.67

- Fixed: after you jump to a room far away, with the room list or the arrows, the game's own keys like E now act on the room you just heard. The mouse pointer used to land while the camera was still moving, so a quick E could switch off the room next to it. Pressing I twice now waits for that room too, so you get its details.
- Fixed: when a room can't be built, the build ring now gives the game's own reason in your language, like "Missing technology". The ring also reads each segment as soon as the game shows it, instead of after a fixed pause.
- Fixed: the tech tree reads a new category as soon as the game has shown it.
- Fixed: Enter on the Battery line in the C list now shows its details, like the other lines.
- Fixed: in other languages, each row of the Morale tab is one item again ("76 Crew, Ohne Quartiere, max. Moral -1.200"), hero skills in events and away missions use the game's own words ("Aufgabe Medizin"), and the resources Clear Debris gives back use the game's names. A phrase that comes right after a number, like the base attack power on the Combat tab, is now translated too.
- Fixed: species numbers like Species 116 are read digit by digit in Spanish, Polish, Russian and Japanese as well.
- Fixed: Left or Right on an event option where the game has no hero selected now says "No hero" instead of nothing.

Thanks to firefly82, whose review showed where the mod was guessing instead of listening to the game.

## Tuesday October 20th 2026

Version 0.3.66

- New: the mod's own words now come out in your game's language. If you play in German, Spanish, French, Japanese, Polish, Russian or Simplified Chinese, the words the mod adds to the game's text are spoken in that language too: deck and tier names, room states like on and off, where you are in a list ("5 von 10"), the chances in an event, key hints, and the F1 and Ctrl+F1 lists. Switch the game's language in Settings and the mod follows it.
- Fixed: in German, a tech tree name the game breaks across two lines is now read as one word, like "Verhandlungstaktiken" instead of "Verhandlungs-taktiken".

The translations are brand new, so if a word sounds odd in your language, please tell us on the forum and we'll fix it. Thanks to firefly82, who asked for this one.

## Tuesday October 20th 2026

Version 0.3.65

- Fixed: when a room changes, like when you switch it off with E or a repair finishes, you now hear its new state once. It used to come through several times, or not at all when no mission was waiting on your rooms.
- Fixed: the segments in a room's ring now use the game's own names, in your language, when the mod can't read the ring's centre.

Thanks again to firefly82, who found the better place to listen for room changes.

## Tuesday October 20th 2026

Version 0.3.64

- New: the tech tree has an A to Z list of every technology from all five categories. Press Right past the last category, or Left before the first, and you'll hear each technology with its category, tier and state. Enter takes you to that technology in its own category and opens it, so you don't have to guess where something lives. Thanks to TheRev for asking for it.
- Fixed: moving Up and Down onto a tall room like a turbo lift now says the deck you're on first, like "Deck 7, Turbo lift, decks 2 to 9". Before, you heard the same "Decks 2 to 9" on every deck and it sounded like you were stuck.
- Fixed: in a room's ring, the mouse pointer now points at the segment in any window shape. In a 4:3 window it missed, so the game's reason a segment was locked never came through.
- Fixed: a locked ring segment with no reason from the game now just says "Not possible", instead of guessing that the ring was out of date.
- Fixed: in other languages, the game's own words are used for energy, crew, cycles and research points in room details and the tech tree, and names like "Holodeck" and "Turbolift" are no longer split in two. In German you'll hear "18 Zyklen verbleibend" instead of "18 cycles verbleibend".
- Fixed: a room's details list keeps its name and its energy apart, like "Science Laboratory, -7 energy".
- Fixed: the Engineering office no longer repeats the ship's hull after everything it reads in other languages.

Thanks to firefly82 for another careful review.

## Tuesday October 20th 2026

Version 0.3.63

- Fixed: points and star systems hidden inside a nebula now use the game's own word for unknown in your language, like "Unbekannt" in German, instead of the English "Unknown".

## Monday October 19th 2026

Version 0.3.62

- Fixed: after a battle, "Injuries: none" and "Damaged rooms: none" now come out right in every language. The mod reads the game's own lists instead of guessing its word for "none", so the German game no longer says "Injuries, 1: K/A". Thanks to firefly82 for working out where the game keeps them.
- Fixed: in other languages, star system numbers are now read digit by digit, even when a name follows the number, and without the English "oh" and "point". English still says "System 8 2 4 oh point 3".

## Monday October 19th 2026

Version 0.3.61

A few more fixes for players using the game in another language, from firefly82's review.

- Fixed: in a story conversation, a choice's chance now reads cleanly in every language, using the game's own word for it. In German, "Erfolgschance: 70%" used to come through raw.
- Fixed: when you press Enter on a locked action in a room's ring, you now hear the game's own reason in your language, like "Not possible: No Life support". In other languages it used to tell you the ring might be out of date instead.
- Fixed: star systems on the Sector Map keep the game's own word before their number in every language.

## Monday October 19th 2026

Version 0.3.60

- Changed: the little key reminders Voyager Access adds, like "R repeats the line", "Left and Right choose another" and "Enter to choose a hero", are now said the first two times only. After a couple of hours of play they were getting in the way of the story. F1 and Control F1 still list every key whenever you need them.
- New: pressing Enter on a choice or button you can't use now tells you so, and why, when the game gives a reason, like "Not available. Needs Science Laboratory Level 0." Before, Enter just did nothing. Thanks to stickbear for this one.

## Monday October 19th 2026

Version 0.3.59

- Fixed: at a point of interest where an option can take a hero, Left and Right could name one hero while a different one went on the mission. The game moves its own choice of hero with those same keys, and the mod was keeping a separate count that drifted. Now Left and Right say the hero the game has actually moved to, and Enter sends that hero. If you came across this in 0.3.58, I'm sorry about that.
- The option now says which hero will go before you press anything. The game starts on the best available hero, so you only need Left and Right if you'd rather send someone else.

## Monday October 19th 2026

Version 0.3.58

- New: at a point of interest where an option can take a hero, Left and Right now give each hero's chances, the same bar a sighted player sees with the mouse on that hero's portrait. For example, "No hero" might be 20% good and 75% bad, while Chakotay brings it to 35% good and 60% bad. Once you've picked a hero, the option reads that hero's chances too.
- New: in the Overview, Up and Down go through the open tab line by line, so you don't have to hear the whole tab again to find one number. Each row is one item: a morale condition with its crew and max morale, a morale level with its effects, a combat room with how many you've built and their combat power. Home and End go to the ends, and Enter repeats the line. Thanks to firefly82 for the idea.
- New: in the tech tree, each technology says what it builds on, like "Cargo Bay Level 2, builds on Cargo Bay", the way the lines between the fields show it on screen. It also says when the game marks one as important or as unlocking a feature. Thanks to firefly82 for working this out.
- Fixed: in an event with two hero options, the second option could start with the hero you'd chosen on the first one.
- Fixed: technology names that wrap onto two lines in the game are read as one word again.

## Monday October 19th 2026

Version 0.3.57

The game's hover tooltips are now yours too, as lists you can take your time with.

- New: in the C list, press Enter on a line to hear its details as the game's tooltip shows them. Morale gives the most you can reach right now and what's pulling it down, like crew without quarters or emergency rations. Hull gives its damage and repair rate, threat gives your strength against the average enemy's, and every resource has its description, capacity and production. Backspace or Escape takes you back to the C list.
- New: in the ship view, press I twice for the room's details: its level, energy, crew, and what E does there and what it costs, like "E: Repair, 8 duranium, 4 tritanium".
- A room more than one deck tall can now be reached on every deck it covers, not just its lowest. Thanks to firefly82 for this one.
- Equinox DLC: the Equinox's decks are now numbered 1 to 8, and the System Map gives travel times in Q Trials again, so you hear "1 cycle away" and Set course works on the Equinox.
- Away missions: when your team meets the requirement, you now hear "requirement met, outstanding success chance 5%" instead of a low "success chance" for a choice that can't fail. Thanks to firefly82 for working this out.
- Species numbers like "Species 1 1 6" are read digit by digit in German, French and Polish too.

## Monday October 19th 2026

Version 0.3.56

Most of these come from firefly82's second review, so a big thank you to firefly82.

- Fixed: the game's E, F and T keys act on whatever room is under the mouse pointer, not the room you just heard, so E could switch off a different room and T could demolish one. Now the mouse pointer moves onto each room as you arrow to it, and the camera goes there first when the room is off screen. E, F and T act on the room you heard.
- After E, the room window or a finished job, the room now says its new state, like "Science Laboratory, off". Before, a wrong E went by in silence.
- Fixed: in the tech tree, Enter could start the research whose details were still open instead of the one you'd moved to. Enter on another technology now opens its own details first.
- You can now abort a research: its details say "Enter aborts the research".
- The room power button and finished work ("done, Enter finishes it") now work in every language the game has, not just English, and the research time left says "cycles" in every language too.
- The Overview's Warp Core tab says "plus 12 energy bonus" instead of a bare 12.
- The key list (Ctrl+F1) now says what E does in the ship view (the room's quick action), and adds F (upgrade) and T (demolish).

## Monday October 19th 2026

Version 0.3.55

One fix for repairs and building.

- When a Construction Report comes up during a trip, it offers Enter Ship as well as Close. If you picked Enter Ship, the finished room stayed "repairing done" and there seemed to be no way to finish it. That room now says "Enter finishes it", and when you press Enter it tells you the room is on.

## Monday October 19th 2026

Version 0.3.54

A small one, with a change you might notice right away.

- Event chances are now rounded to the nearest 5 percent, like "55% chance of an excellent outcome, 45% chance of a bad outcome". The exact numbers sounded more precise than anything the coloured bar shows a sighted player, and they still add up to 100.

## Monday October 19th 2026

Version 0.3.53

Fixes found while playing sectors 8 through 11 of the campaign.

- Fixed: the "You still have unassigned slots. Continue?" warning, in the away team setup and before a battle, could lose the arrow keys to the screen behind it, and then nothing worked. Up and Down now stay on Return and Continue until you answer.
- Fixed: Up and Down in a story choice list could jump past a choice that wasn't available. Every choice is reached now, in order.
- Away missions: a hero who can't take a choice now says so and why, like "cannot take this choice, needs the Saboteur trait". Before, you only found out when Enter was refused.
- Rooms that are more than one deck tall name their decks ("Decks 4 to 6, Holo deck"), and when one of those decks has no life support, the room says which one.
- Incoming calls: Up and Down stay on the calls instead of wandering off to a room's buttons.
- An injured or sick hero's condition is said once in the hero list, not twice.
- When a point's event doesn't open because another window was up as you arrived, that message is no longer cut off by the map announcement.

## Sunday October 18th 2026

Version 0.3.52

A fix for the end of the first mission, plus one for away missions.

- Fixed: after you chose to destroy the Caretaker's Array, Enter on "Fire" did nothing, so the story couldn't go on. The game puts "Fire" on the same button as the choice before it, and the mod took it for the choice you'd already made. Thanks to stickbear for the report.
- Fixed: the end of an away mission could give a hero someone else's rank, and sometimes a rank partway through counting up. Each hero now gets their own final rank and experience, in the team's order.

## Sunday October 18th 2026

Version 0.3.51

One fix for away missions that matters.

- Fixed: when you pressed Enter on a hero you'd already picked for a challenge, the game took them off the team, but the mod still said "selected". So Confirm could send a different team than you thought, with a much lower chance. A hero is only "selected" now when the game really has them on the team, and the success chance you hear matches who's going.

## Sunday October 18th 2026

Version 0.3.50

Two small ones from a new Q Trial.

- Fixed: when a room won't switch on, the mod used to name your energy, like "Did not switch. Energy 108, rooms use 51", even with plenty to spare. It only names the energy now when it's really short. Otherwise it says "Did not switch. The game shows no reason", because the screen doesn't show one either.
- Fixed: in the Q Trials setup, a hero slot you'd emptied in the hero picker still read the last hero's name. It reads "empty" now, as on screen.

## Sunday October 18th 2026

Version 0.3.49

Found while flying a Q Trial through the Hazari and Nebula sectors.

- Changed: inside a nebula the game hides what each point is, and its own label just says "Unknown". The mod says "Unknown" there too, on the System Map and the Sector Map, instead of naming the planet. You still hear whether it's scanned and how far away it is.
- New: in a battle, I names a recruited ally and its hull, like "Ally: Maquis Raider, hull 100%". The screen shows the ally under the objective, and the mod left it out.
- Fixed: a battle result read the experience you gained as two items, "Experience, 127". It's "127 Experience" now.

## Sunday October 18th 2026

Version 0.3.48

Away missions tell you your odds now, which firefly asked about.

- New: when a hero's skill is below what a challenge needs, the game works out a success chance, and the mod says it. You hear it when you pick the hero and again on Confirm, like "Confirm with Joe Carey, success chance 45%". If the skill is high enough, there's no chance to say, just as on screen.
- Fixed: in the Leave Sector window, Stay for now couldn't be reached with the arrows, although the list counted it. It can now, and the window's heading is read before the first sector instead of after it.
- Fixed: when a side mission or a main mission ends, its window reads what happened before its button. The button used to come first.

## Sunday October 18th 2026

Version 0.3.47

Sector 7 to the end, and a lot from firefly82's two-hour playtest. Thanks, firefly, and thanks to NightCraller302 for the event report.

- New: map points and star systems say how far away they are, like "Debris Field, not scanned, 4 cycles away". It's the same number the game shows under a selected point, so you can tell three Class Y planets apart and save fuel. This is firefly's patch, word for word.
- Fixed: in the German game, system numbers like "4.048.1" came out as "4 point oh 4 8, .1". They're said "4 oh 4 8 point 1" now. Also firefly's.
- New: if Voyager arrives while another window is up, like a mission offer that came halfway through the trip, the game skips that point's event. The mod tells you now: the event didn't open, so set course to another point and back.
- New: hero lists in battles and away missions say why a hero can't go, like "Chakotay, unavailable: severely injured, 20 cycles" or "Harry Kim, unavailable: away".
- New: battle targets name their part of the ship, like "Engines, aft, 40 health". A Hirogen scout had three targets all called "Engines" before.
- New: an empty building space on a deck whose life support is off says "no life support", and Enter tells you why nothing opens instead of doing nothing.
- Changed: a tutorial is held until you press a key, however long your screen reader takes. Anything that comes in meanwhile waits behind it instead of cutting it off. Thanks, firefly.
- Changed: the build ring reads each room right away. It used to wait half a second for a mouse hover that never helped.
- Fixed: after a major decision, each Enter that moved the story on said "Holding" and pressed the old choice again. It just moves the story on now.
- Fixed: each Overview tab is read once when you switch to it, not twice.
- Fixed: one story choice said the game's own "Success Chance: 70%" where the others say "chance 70%". It says "Chance 70%" now.
- Fixed: the energy loss report read "Warp. Core damaged" when the name was wrapped onto two lines. It's "Warp Core damaged" again.

## Saturday October 17th 2026

Version 0.3.46

More from the Hirogen relay stations in sector 7, including two fixes that matter.

- Fixed: when you start a battle or an away mission with empty hero slots, the game asks "You still have unassigned slots. Continue?" Its Return and Continue couldn't always be reached, so you were stuck on the setup. They take focus now.
- Fixed: Home in an away team's hero list jumped out to the team slots instead of going to the first hero. That broke in 0.3.43 and works again.
- Changed: a battle result names two damaged rooms of the same kind once with a count, like "Life Support times 2".
- Fixed: the Workshop no longer says "No blueprints to craft" while it's busy crafting something.

## Saturday October 17th 2026

Version 0.3.45

A quicker V, and a stray number. Thanks, TheRev, for the report about sluggish keys.

- Changed: V says "Ship view" or "System map" the moment you press it. Before, it waited about a second and a half for the camera to finish moving. The room or point you're on follows once the view settles.
- Fixed: some event options read a placeholder reward, like "Leave for now. Up to #999 deuterium" at the Hirogen relay stations. That's gone now.

## Saturday October 17th 2026

Version 0.3.44

A good going-over of the Overview.

- New: the Overview's Q Trials tab reads its challenge levels as a list, like "Level 2, not active: Spatial phenomena spawn 50% more often. Crew treatment time increases by 60%." Before, the words came out jumbled with the count in the middle.
- Fixed: going back to an Overview tab you'd already visited could say nothing, especially the Heroes tab. Every tab is read each time you switch to it now.
- Fixed: on the Q Trials tab, Down went to CLOSE after switching tabs, and Right could wander into the Q Modifier picker. Down now starts on the active level, and Left and Right only switch tabs.
- Changed: the Heroes tab says the name first, like "Neelix, rank 1" instead of "Rank 01, Neelix".
- Fixed: the HUD's cycle counter said only a number when it got focus. It says "Cycle counter, 24" now.

## Saturday October 17th 2026

Version 0.3.43

From a couple of Q Trials, with a Maquis raider along for the ride.

- New: the Bridge's Combat Allies tab reads an ally you've recruited, like "Recruited: Maquis Raider Ally, combat power 51. Upkeep: 30 deuterium per cycle. Enter: Dismiss Ally." The tab also says how many allies you have. Before, every empty slot said "Currently no combat allies recruited", even with one aboard.
- Changed: battle abilities name the hero the way the game does, so you hear "Telek R'Mor" instead of a garbled id like "Telek RMor".
- Changed: a technology the game marks "[NOT WORKING YET]" now says "Not working yet:", and a blank the game forgot to fill in is skipped instead of read out with its braces.
- Fixed: on the Q Trials results, End went to the last reward instead of Confirm. It goes to Confirm now, even right after you pick a reward.
- Fixed: the Combat Allies tab no longer reads a recruitable ally's button as a jumble of numbers, or the same line twice.

## Saturday October 17th 2026

Version 0.3.42

Two good questions from the forum, and more work on playing in other languages. Thanks, SightlessPsycho!

- New: on the System Map, a point you've already finished says "done", like "Shipwreck, done". Flying back there opens nothing, so now you know before you go. Any other point opens its event by itself when Voyager arrives.
- New: each tier in the tech tree names the technologies it opens, like "Tier 2, available, opens 9: Workshop Level 2, Hyperspanner, Cargo Bay Level 2..." Before, you only heard "Tier 2".
- Fixed: when the game isn't in English, room tabs and the Overview tabs are now found and read.
- Fixed: an event's "Better with" names the room in the game's own words and language.
- Fixed: numbers grouped with a space, like "1 170" in French, are said as one number.

## Saturday October 17th 2026

Version 0.3.41

From the campaign's sector 7, and a careful outside review by Firefly. Thank you!

- New: in battle, choosing an order says so, like "Repair Weapons ordered" or "Targeting Warp Core".
- New: the Workshop says "Crafting Torpedo started" when you start a blueprint.
- Changed: rooms use the game's own names, so the ship view matches everything else ("Navigational Deflector", "Bio Laboratory", "Shield Generator"), and the names follow the game's language.
- Changed: Species 8472 is said "8 4 7 2", the way the crew says it.
- Fixed: after answering a call, a No Way Back warning that came up couldn't be answered, because its YES and NO couldn't be reached. They can now.
- Fixed: Escape could leave the Overview half open, so it said nothing the next time you opened it.
- Fixed: the Workshop said "No blueprints to craft" while blueprints were listed.
- Fixed: the battle status could list the same hero ability twice.
- Fixed: a locked ship in the Q Trials setup wasn't said as locked.
- Fixed: on an away mission, a choice with no heroes listed now says so instead of saying nothing.
- Fixed: the DLC cards relied on the English word "Installed", so in other languages Enter on a DLC you own could open its store page.
- Fixed: UE4SS came with its developer keys switched on, and Ctrl+J or Ctrl+H could freeze the game. They're off now.
- Changed: the game log now lists the keys you press, so a report shows what happened just before a problem.

## Saturday October 17th 2026

Version 0.3.40

More from the Scorpion sector, mostly about knowing why things happen.

- New: C now says why the hull is changing, like "Hull 57, minus 12 per cycle: deflector offline minus 15, repairs plus 3. Main deflector damaged." Before, you only heard the total.
- New: saving says so. You hear "Manual Save" after saving from the menu, and "Autosave" when the game saves by itself.
- Fixed: when only a number in an objective changed, like "-10 FOOD per cycle" becoming "-20", it was said as "Done:" and then as a new objective. It's now said once as "Changed:".
- Fixed: after a Game Over and Reload Save, the objectives could say "Done:" or "Mission ended" for things from the game you'd just lost. They're read once, fresh, after the reload.
- Fixed: a finished task that had a countdown in it was said with the number missing ("within CYCLES").
- Fixed: the construction ring could refuse a room you could now afford, if the resources came in while the ring was open, and once it gave the room's description as the reason. It checks the game's current data when you press Enter.
- Fixed: the Science Laboratory said "1 of 2" when no analysis was running, though the second item couldn't be reached.

## Saturday October 17th 2026

Version 0.3.39

More fixes from the campaign's Scorpion sector.

- New: the game shows a cost you can't pay in red. Repair, upgrade and blueprint costs now say "not enough" after that amount, and the construction ring names what you're short of and how much you have, like "Missing resources: Duranium, 38 of 80."
- Fixed: objectives said "Done:" every cycle on a task with a countdown in it ("within 36 cycles"), and on counts over 999. Only finished tasks are announced now.
- Fixed: a room that had just started building could be read as "on". It says "building" and the cycles left.
- Fixed: after you built a wide room, the ship view could name the empty space beside it. It stays on the new room.
- Fixed: the Science Laboratory didn't say when a research had paused an analysis. The analysis now says "paused".
- Fixed: right after Repair, the ship view could still say the room was on. When that happens it says the new state a second later.

## Saturday October 17th 2026

Version 0.3.38

Fixes from playing the campaign into sector 6.

- Fixed: hero lists said injured heroes were at full strength. They now say "injured" or "severely injured" and read the skill values the game really uses, like "Joe Carey, injured. Command 13, Diplomacy 12, Engineering 20" instead of 26, 24 and 40.
- Fixed: an away team screen could be read with the previous away mission's description and recommended skills. It reads the mission that's actually on screen now.
- Fixed: in battle, L could list the same ability three times when one hero filled the team. Each ability is said once.
- Fixed: after a Game Over in the Q Trials, the results said "Select a reward, 0 of 0". That line is left out when there's nothing to select.

## Friday October 16th 2026

Version 0.3.37

Smaller fixes from exploring the Q Trials.

- Fixed: a few buttons didn't say anything when you pressed them, though their wording changed. In the Engineering Office, pressing Enter on "Unassign from hull repair" now says "Work Team 1, currently unassigned. Assign to hull repair", and the other way around.
- Fixed: some event results read leftover numbers that weren't real, like "#999 deuterium. 0 duranium stored" after a reward that didn't fit in storage. They're left out now.
- Fixed: costs to leave a Q Trials sector said "SciencePoints". They say "289 science points" now, and research rewards read their resources the same way.

## Friday October 16th 2026

Version 0.3.36

Tutorials you can actually finish hearing.

- Fixed: a tutorial could get cut off by the next message, like an event or a report opening right behind it, and since tutorials close by themselves there was no getting it back. Now the next message waits until the tutorial has been read, unless you press a key.
- Changed: pressing R again within 5 seconds goes back one more message each time, like "Earlier: Tutorial: Help...". So if you miss something, R and then R again brings it back.

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

Version: 2.11.4
2026/10/30 Released

💪 Improvement
- [Reset] When a specialization finishes the pool of a boss or dungeon, its marks are cleared to start a new cycle, as before, but now the chat tells you and shows an [Undo] link: clicking it puts the marks back. Nothing to type.

🛠️ Fix
- [Loot data] Raid tier tokens are back in the loot lists of every raid boss (version 2.11.3 removed them by mistake). The curio of Ula'tek is left out on purpose, since a Voidcore cannot give it. Reported on CurseForge.
- [Loot data] Once per version the addon now checks its loot lists against the Adventure Guide by itself (the same as /void audit) and adds any item that was missing, so lists that lost items to an older version heal without doing anything. It says one line in the chat when it adds something.
- [Detection] A roll is now marked even if the addon has just loaded and is still preparing its loot lists; before, it could be missed until a later login. The same goes for finishing the pool of a specialization.
- [Scan] Reading the Voidcache tooltip no longer depends on the line where the item list starts or on its dash marker, and a tooltip the addon cannot understand never offers a whole pool as obtained.

---

Version: 2.11.3
2026/10/30 Released

🔮 New
- [Scan] The Voidcache scan of dungeons and of raids, and `/void scan owned`, no longer mark anything by themselves. When they finish they open a window with every item they found (name, boss or dungeon and specializations), all unticked: you tick the ones you really got from a Voidcore roll and press the button. Closing the window changes nothing. Select all and Select none buttons are included.
- [Scan] A scan only adds marks now. It no longer clears the marks you already had for that content (rolls the addon detected or items you marked by hand). The previous marks are still saved, so `/void restore` undoes the last scan.
- [Scan] After marking, the chat tells you how to undo it: `/void restore` undoes the last scan, or you can unmark an item in Mark rolled item mode.
- [Scan] The scan window has its own color, green by default, and a Color button in its header, next to the X, that opens a palette with every theme of the addon. The choice is saved.
- [Loot data] New `/void audit`: it reads every raid boss of the season from the Encounter Journal, compares it with the addon's loot lists and adds any item that was missing, for every class and specialization. It never removes anything, tells you in the chat which boss lacked which items and keeps the result for the next sessions.

🛠️ Fix
- [Loot data] Only gear that gives item level is tracked now. Mounts, pets, tokens, shirts and cosmetic armor are removed from the loot lists of every raid boss and dungeon when the addon loads, and the reader of new raids skips them too. An item the game cannot identify yet is kept, so nothing real is dropped.
- [Scan] The scan no longer offers the trinkets that the addon adds to the tank specializations (damage trinkets of the same main stat), which the game does not list in the Voidcache tooltip. They could be marked as obtained on characters that never rolled them. Reported on CurseForge.
- [Scan] `/void scan owned` skips trinkets.

---

Version: 2.11.2
2026/10/30 Released

🔮 New
- [Scan] The Voidcache scan of dungeons and of raids, and `/void scan owned`, now show the list of items they are about to mark and ask for confirmation before saving. If you cancel, nothing changes.
- [Scan] After a scan that marks items, the chat tells you how to undo it: `/void restore` undoes the last scan, or you can unmark an item in Mark rolled item mode.

🛠️ Fix
- [Scan] The scan no longer marks the trinkets that the addon adds to the tank specializations (damage trinkets of the same main stat), which the game does not list in the Voidcache tooltip. They could be marked as obtained on characters that never rolled them. Reported on CurseForge.
- [Scan] When a scan would mark almost a whole pool (at least 5 items and more than 60% of it), that pool is ignored and the chat says so, because it looks like the tooltip and the data do not match. The marks that pool already had are kept.
- [Scan] `/void scan owned` skips trinkets.

---

Version: 2.11.1
2026/10/30 Released

💪 Improvement
- [Detection] The item in the "detected automatically as obtained" chat message is now clickable. Clicking it shows the tooltip of the item you own, with its real item level and bonuses (looked up in your bags, then in what you have equipped; the one with the item level of the message if you have several). If you no longer have it (sold or thrown away) it shows the normal tooltip of the item.

---

Version: 2.11.0
2026/10/29 Released

🔮 New
- [Roll window] Ten layouts for the bonus roll window: classic, wide, tall card, compact bar, spec list, ring, banner, two columns, minimal and big button. They all show the same information arranged differently. Pick one in the settings (bonus roll tab); the new Preview button there opens a sample beside the settings and it changes live as you switch layout, and pressing it again closes it.
- [Settings] The settings window has its own color theme, in the General tab right above the color theme of the other windows. It uses the same 22 themes (and "My current theme"), and is green by default.

💪 Improvement
- [Roll window] The position of the roll window and its layout are independent. Move window opens the sample where you left it (beside the settings the first time) and you drag it from there; a new Save button, only visible while you move it, closes the sample. Trying a layout never changes the saved position, and moving never changes the layout.
- [Settings] The theme selectors and the new layout selector are one dropdown button (swatch, name and a "v") with an arrow on each side: the arrows go one by one, the button opens the whole list. The font selector is as wide as they are.
- [Roll window] The spec numbers over the icons (compact bar, ring, banner and big button layouts) are bold and sit on a dark patch, so they can be read.

---

Version: 2.10.0
2026/10/29 Released

🔮 New
- [Roll window] The bonus roll window can now be moved: drag it with the left mouse button and it stays where you drop it, for real rolls and for the preview. A new row in the settings (bonus roll tab) has a Move window button, that opens the sample window so you can place it, and a Reset button that sends it back to its default spot.

💪 Improvement
- [Panel] With no specialization clicked in the spec ranking, the loot panel no longer shows your current loot specialization ("Loot:") nor tints the items of other specializations red. Both only happen after you click a specialization.

🛠️ Fix
- [Roll window] The full roll window (your odds, the specialization ranking and the wanted items) now appears for every raid boss, including new ones such as Kith'ix, instead of the plain window with only the timer and the buttons. When the Voidcache item of a boss is not in the addon's table, the boss is now found from the name in the roll title or from the last boss you killed.

---

Version: 2.9.3
2026/10/28 Released

🔮 New
- [Scan] `/void scan owned` marks, for your current loot specialization, every pool item you have equipped or in your bags. It is for items you bought with Voidcores before the addon saw the roll, or that the Voidcache tooltip does not drop. It cannot tell a Voidcore roll from a normal drop, so unmark any that did not come from a roll.

🛠️ Fix
- [Detection] A Voidcore roll now marks the item only for the loot specialization you rolled with, not for every specialization that can get it. Reported on CurseForge.

---

Version: 2.9.2
2026/10/28 Released

🛠️ Fix
- [Release] The changelog shown on CurseForge and in WowUp no longer has garbled characters (the emojis of the titles and the ellipsis). Nothing changes inside the addon.

---

Version: 2.9.1
2026/10/28 Released

🔮 New
- [Scan] `/void scan owned` marks, for your current loot specialization, every pool item you have equipped or in your bags. It is for items you bought with Voidcores before the addon saw the roll, or that the Voidcache tooltip does not drop. It cannot tell a Voidcore roll from a normal drop, so unmark any that did not come from a roll.

🛠️ Fix
- [Detection] A Voidcore roll now marks the item only for the loot specialization you rolled with, not for every specialization that can get it. Reported on CurseForge.

---

Version: 2.9.0
2026/10/27 Released

🔮 New
- [Panel] The panel, the raid overview (the list of bosses) and the dungeon overview now stick to the Adventure Guide by default, aligned with it and following it when you move the guide. A new pin button next to the X, in the three windows, switches between pinned and free: while it is pinned the window stays attached; if you drag it by its title row (or press the pin) it is released and keeps the position you give it, and pressing the pin again sticks it back. The pinned or free state is the same for the three windows. /void resetpanel pins it again. The button has a tooltip that says what it does.
- [Settings] A new "Text size" control in the General tab: the - and + buttons make the text of the addon and all its windows smaller or bigger (80% to 160%, in steps of 10%) and a Reset button goes back to 100%. The choice is saved. Windows that are already open need to be opened again to show the new size completely.
- [Panel] The "Mark rolled item" button is orange instead of red while mark mode is on ("Click to save"), with a lighter orange on hover, so it no longer looks like a warning.
- [Scan] The Voidcache scan of dungeons and of raids now writes its progress in the chat: a line each time it passes 10%, with the steps done, for example "Scanning… 30% (7/24)", up to 100% before the final summary.
- [Roll window] The line that says where the roll comes from is now colored like the log parses: a Mythic+ key is grey at +2, green at +3 and +4, blue at +5 and +6, purple from +7 to +9 and gold (the color of a perfect parse) at +10 and above; and for a raid the difficulty in brackets is green on Normal, purple on Heroic and gold on Mythic, so you can see at a glance where a Voidcore is worth spending.

🛠️ Fix
- [Roll window] The name and the number of items of each specialization chip now belong to the chip, so they are hidden and shown together with it instead of staying on screen when the chip is hidden.
- [Fonts] The text of the addon no longer grows when another addon makes all the game fonts bigger. The addon fonts used to copy the size of the game fonts, so with such an addon the windows (for example the bonus roll window) showed text that was too large and covered other lines. They now keep their own fixed sizes, the addon puts them back if another addon changes them, and checks them again when you enter the world.

---

Version: 2.8.2
2026/10/25 Released

🛠️ Fix
- [Languages] Messages that were written only in English now follow the language of your game, in all 11 languages: the report of the Voidcache scan with its hints, start and cancel messages, "Key detected" and "Raid detected", the warning when the loot data is missing, "Finished loading", the messages of /void liveraid, /void replaylog, /void rolls and /void tooltips, the title of the bonus roll window when the item is not known yet and the "Warming cache" line of the raid overview. The /void debug report stays in English on purpose, so it can be read when it is pasted in a bug report.
- [Scan] The confirmation of the raid scan always said "Mythic" in ten languages, even when you were scanning Normal or Heroic. It now shows the difficulty you are scanning. Two typos fixed in the scan confirmations (German and Spanish).

---

Version: 2.8.1
2026/10/25 Released

🛠️ Fix
- [Scan] The scan of the Voidcache now reports what it did when it finishes: how many tooltips it read, how many could not be read in time or did not match any item name, how many item names the game had not loaded yet, and what to try when nothing was marked (the dungeon scan only reads keystone +10, raid rolls need the raid scan of the difficulty you rolled on). Reported on CurseForge by a user whose scans found none of their rolled items.
- [Scan] A tooltip that could not be read in time used to count as empty, so the scan marked every item of that dungeon or boss as obtained and cleared what you had marked there. Now such a pool is skipped, the marks you already had in it are kept, and the scan tells you how many were skipped.

---

Version: 2.8.0
2026/10/24 Released

🔮 New
- [Roll window] A cleaner bonus roll window. The item name takes the first line and under it comes where the roll is from: the boss with its difficulty for a raid (for example Ula'tek (Heroic)) and the difficulty with the key level for a dungeon (for example Mythic +10). The cost line follows, and your specializations are now chips with their icon, name and the number of items left (the ones you chose in brackets); the active one is outlined and clicking another one switches your loot specialization. Reported on CurseForge.
- [History] The items of the roll history (/void history) can now be used: hover one to see its tooltip, Shift-click it to put the link in the chat and Ctrl-click it to try it on.

🛠️ Fix
- [Roll window] Long item names, such as "Nebulous Voidcache: Prey", wrapped over the cost line. The header now measures the name and everything below it moves down, so nothing overlaps.
- [Settings] In the Tools tab the command written in each square (for example /void missing) touched the bottom border and stuck out depending on the font. The squares are a little taller and the command is anchored to their bottom, so it always stays inside.

---

Version: 2.7.3
2026/10/24 Released

🛠️ Fix
- [Tooltip] Some raid items lost their "Equip:" effect text in the tooltip, for example the plate legs of Ula'tek (Unbound Rancor Legguards). Those items only show the effect when their link carries one extra bonus ID. Instead of listing the items by hand, the addon now compares the tooltip with the plain item's and, when an effect line is lost, rebuilds the link with that bonus and keeps it if the effect comes back. It works for every item of the season raids, on Normal, Heroic and Mythic and for every armor type. The new command /void tooltips checks all of them in game and lists any item that still loses an effect. Reported on CurseForge.
- [Overview] When you chose items that no single specialization can loot (for example a tank weapon and a damage weapon of the same class, plus a neck and trinkets), every specialization was marked as unable and the overview showed the first one, such as Holy for a Paladin, with a 0% drop chance. Now the specializations that cover the most of your chosen items are used and ranked, and the chance shown is the one for the items they cover. Applies to the raid and dungeon overviews, the specialization ranking and the reminder. Reported on CurseForge.

---

Version: 2.7.2
2026/10/23 Released

🔮 New
- [Panel] A new look for the "Mark rolled item" button at the bottom of the loot column. While you can press it, it is filled with the color of your theme and glows when you hover it. Once mark mode is on it turns a muted red, with a lighter red on hover, to show that pressing it again saves the marks and leaves the mode. Both states follow the theme you chose, and the gold bar and the white line on top are gone.

---

Version: 2.7.1
2026/10/23 Released

🔮 New
- [Detection] The chat message that says an item was detected as obtained through a Nebulous Voidcore now shows the item level the roll gave, in parentheses next to the item, so a wrong difficulty is easy to spot.

🛠️ Fix
- [Detection] A bonus roll was filed under the boss, dungeon or difficulty open in the panel instead of the one the player was really in. For example a Heroic roll could be saved as Mythic when a Mythic boss was on screen, and a Mythic+ roll lost its key level, so a +2 to +9 roll (Heroic track pieces) could be counted with the +10 and higher ones (Mythic track pieces). Now the keystone or raid you are in, or just left, always wins; the panel only fills in when there is no real context, as in the open world.
- [Detection] The difficulty of a raid roll is now also read from the rolled item itself (its link says whether it dropped on Normal, Heroic or Mythic). Rolls saved by older versions without a difficulty use the item level, and if it cannot be told nothing is marked instead of guessing. Rolls already saved with the wrong difficulty are corrected the next time the roll log is checked, and the marks they left on the wrong difficulty are removed unless another roll or a manual mark of that item backs them.
- [Panel] An item you unmarked came back after relogging, because the saved roll that had detected it was applied again at login. Unmarking an item now also tells the log not to mark it again; the roll stays in /void rolls and the history.

---

Version: 2.7.0
2026/10/23 Released

🔮 New
- [Raid Overview] "Select by slot" for raids, the same wishlist the Dungeon Overview has: a grid of equipment slots at the bottom of the raid overview. Press a slot to open a list with every item of that slot your class can loot in the raid (on the difficulty you are viewing) and tick the ones you want; each item is chosen on every boss that drops it. "Select All" chooses them all and the red x clears the choice. Suggested on CurseForge.

🛠️ Fix
- [Loot] Tank specializations could not choose the damage trinkets that the Adventure Guide shows them (for example Zul'jin's Guillotine Technique for a Protection Paladin), because the loot tables listed those trinkets only for the damage specializations. Tanks now also get the trinkets of the damage specializations of their class that use the same main stat: Protection Paladin with Retribution, Protection Warrior with Arms and Fury, Blood with Frost and Unholy, Guardian with Feral, Brewmaster with Windwalker and Vengeance with Havoc. Reported on CurseForge.

---

Version: 2.6.1
2026/10/23 Released

🛠️ Fix
- [Detection] When all the items of one loot specialization were obtained (by hand with the Mark bar, with the bag icon, or by a real roll), the addon reset every specialization of that boss, so you lost the progress of the others. Now only the specialization whose pool ran out starts a new cycle; the rest keep their marks. Reported on CurseForge by a user who was missing one item for Restoration while the Enhancement pool was finished.

---

Version: 2.6.0
2026/10/22 Released

🔮 New
- [Bonus Roll] New layout for the bonus roll window: the item, its cost and your loot spec on top; a panel with your chance of one of the chosen items (big figure) next to the icons of those items; a row with your specializations; the timer bar; and the Roll and Pass buttons.
- [Bonus Roll] Click the icon of any other specialization in that row to switch your loot specialization to it. The active one is outlined in the color of your theme and clicking it does nothing.
- [Fonts] New "Font" option in the settings (General tab) that changes the font of the addon and all its windows at once. The list shows the fonts of the game, Source Sans 3 (included with the addon) and every font that other addons register with LibSharedMedia, so if you have an addon that adds 200 fonts, you can pick any of them. Each name is written in its own font, and "Game font (default)" puts everything back.

💪 Improvement
- [Settings] The theme selectors have a drop-down: click the name to open the list of all the themes, each with a swatch of its color (the arrows still step through them). The names "Style of my class" and "Same as my theme" are shorter ("My class" and "My theme") and the Preview button is wider, so nothing runs out of its box.
- [Settings] The Version page is laid out from the height of each block, so the credits no longer run into the address, and the CurseForge address has its own full-width box.
- [Settings] Shorter names on two Tools buttons so they are not cut.
- [Settings] Every page of the settings window scrolls, with a slim bar in the color of your theme and the mouse wheel, so long pages (the General tab with the new Font option) no longer run past the bottom of the window.
- [Panel] In the spec ranking the bar no longer covers the "0/3" count (it stops before the column of figures), the rows have more room, the rank numbers (#2, #3) are no longer cut to "...", the loot spec line has more space around it and shows only the name of the specialization, without its icon.
- [Support] `/void perf` showed the memory in megabytes but labeled it as kilobytes (2 MB appeared as "2 KB"). It now shows MB with one decimal.
- [Bonus Roll] The number of remaining items per specialization no longer shows an empty "(-)" when you chose nothing for it; only the chosen items still missing are shown in brackets.
- [Languages] The new texts are translated into all 11 languages.

---

Version: 2.4.0
2026/10/22 Released

🔮 New
- [Settings] New settings window with side tabs (General, Loot Spec Reminder, Bonus Roll, Tools, Version). It opens with `/void open` or with the "Open settings" button of the addon in the game's Options, and saves the same settings as before. The Tools tab has shortcuts to the missing items, where to spend the next Voidcore, your Voidcores, the roll history, the wishlist import and the panel position.
- [Panel] The spec ranking has a new look: bigger rows with a progress bar under each spec, the chance as the main figure (or obtained/total when nothing is chosen) with the best spec marked by its gold rank and its figure in the color of your theme. The spec you click gets a band and a bright edge in that color.
- [Panel] Items that will not drop for the spec in use (your loot spec, the spec you picked in the ranking, or the specs that cover your chosen items) are tinted red. Dark still means you already got the item.
- [Panel] The loot spec ("Loot: Arcane") now sits on its own line right under the "Spec ranking" header, with the icon of the spec in front of its name, instead of being squeezed next to the title.
- [Theme] The theme preview window has a new "Void stone" look: a double border and a soft glow of the theme color.
- [Settings] New "Version" tab: the version you have, a short list of what it adds and the credits to the original author (rolferik12), with the address of the CurseForge page ready to copy.
- [Settings] When the settings window is opened from the game's Options panel (Esc > Options > AddOns), closing that panel no longer closes the addon's window. Opened with `/void open`, Esc still closes it.
- [Settings] The windows opened from the Tools tab (missing items, where to spend the next one, your Voidcores, the history and the wishlist) also appear beside the settings window, and the report window is wider so the history lines no longer wrap.
- [Settings] The preview windows opened from the settings (theme, bonus roll and reminder) appear beside the settings window, on its left when there is no room on the right, so they never cover it.

💪 Improvement
- [Languages] Every text added in 2.3.1 and 2.4.0 (the commands, reports, weekly summary, settings window and Version tab) is now translated into all 11 languages. Until now those texts showed in English outside English and Spanish. They have not been reviewed by native speakers: corrections are welcome.
- [Tests] The load test also opens every tab of the settings window and checks that `/void open` uses it.
- [Options] The game's Options list now has a single "Open settings" button for the addon instead of three sub-pages.

🛠️ Fix
- [Settings] The "Loot Spec Reminder" tab name was longer than its tab and ran into the page, and long labels and hints overlapped the next row. Tab names are short and cut to the tab, rows grow with their text and have more room between the label and its hint.
- [Panel] In the spec ranking the best spec looked selected even when you had clicked another one. Only the spec you click gets the band and the bright edge now; the best one is marked by its gold rank number and its figure in the theme color.
- [Panel] The difficulty was shown twice next to the boss name after changing the difficulty in the Adventure Guide.

---

Version: 2.3.1
2026/10/22 Released

🔮 New
- [Voidcores] `/void history` now shows the icon of each item in front of its name, and compares how many chosen items the odds of your rolls predicted with how many you got (each roll saves its odds from now on).
- [Wishlist] `/void wish [min gain %]`: with a minimum gain (for example `/void wish 1.5`) the lines of a pasted Raidbots / Droptimizer list that show a smaller percentage are skipped.
- [Notices] Once per week, at login, a chat line tells you how many chosen items you still miss in Heroic and Mythic. Turn it off with "Weekly summary at login" in the options.
- [Characters] The raid overview has an "All my characters" link that opens the list of your characters.
- [Support] New `/void perf`: memory and CPU used by the addon, with the steps to measure it in each situation.
- [Tools] New `tools/build_seasondata.lua` writes `Core/SeasonData.lua` straight from the generator's saved variables (no copy and paste), and `tools/upload_curseforge.ps1` uploads a release to CurseForge.

💪 Improvement
- [Memory] The Missing, Transfer, theme preview and report windows are created the first time they are used instead of at login.
- [Tests] 26 automated tests of the probability, saved data and wishlist parsing (`lua tests/run.lua`) and a load test of every file (`lua tests/smoke.lua`).

🛠️ Fix
- [Voidcores] `/void history` counted rolls of unknown origin as "most rolled" and mixed old entries that never stored whether the item was chosen into the luck percentage. Both are fixed.

---

Version: 2.3.0
2026/10/22 Released

🔮 New
- [Options] New **Preview** button on every theme row. The color theme opens a sample window (also `/void preview`) that recolors live, with a counting-down timer bar and < > buttons to look at other themes without changing yours. The bonus roll theme opens the roll window preview and the reminder theme opens the example popup.
- [Options] New **Bonus roll window theme** and **Reminder popup theme** selectors, both defaulting to your class. Use their Preview buttons to see the result.
- [Options] New `/void open` command that opens the addon options page directly.
- [Reminder] The loot spec popup now also appears in front of raid bosses: target a current-season raid boss before the pull and it shows once per boss. It has its own option (on by default) and boss wording in the warning.
- [Reminder] Both popups use the flat themed look of the sample windows (gold corners, spec rows with a progress bar, no clipped text) and show a gold "Reborn" next to the title. Try it with the Preview button of the reminder theme.
- [Bonus Roll] The timer bar shows the time left (for example 2:34) in its center.
- [Panel] **Mark rolled item** works in two steps: press the bar, click the items you got (they dim right away), then press "Click to save". Closing the panel or changing boss discards unsaved marks.
- [Panel] The panel title now shows the difficulty next to the boss or dungeon name: [Raid Finder], [Normal], [Heroic], [Mythic] for raids and [Mythic+] for dungeons, each in its own color.
- [Panel] New line under the spec ranking with the chance to get at least one chosen item with 1 roll, 3 rolls and with the Voidcores you have. Turn it off with "Show cumulative odds" in the options.
- [Voidcores] New `/void cores [14|15|16]`: Voidcores you have, spent this week, and about how many you need to get everything you chose.
- [Voidcores] New `/void next [14|15|16]`: raid bosses and dungeons ranked by your chance of a chosen item. Bosses killed this week go last and the dungeon of your keystone gets a bonus.
- [Voidcores] New `/void history`: your last 200 rolls, how many gave a chosen item and where you rolled most.
- [Wishlist] New `/void prio <item> bis|alt|clear` (full or half weight). Priorities now weigh the spec ranking and `/void next`.
- [Wishlist] New `/void wish`: paste item IDs, links or a Raidbots / Droptimizer list and they are chosen everywhere they drop.
- [Panel] New green + button (and `/void select [clear]`) that chooses everything your loot spec can still get from the open boss or dungeon.
- [Characters] New `/void chars`: Voidcores and missing chosen items of each character, saved when you log out.
- [Reminder] After a wipe, the popup appears again on the next pull of that boss.
- [Live Raid] When the loot data is missing a new raid, a banner appears at the top of the screen as well as the chat message.
- [Support] New `/void debug`: version, settings and recent messages in a window you can copy into a bug report.

💪 Improvement
- [Bonus Roll] The timer bar refreshes 10 times per second instead of every frame, using less CPU. The theme preview does the same.
- [Missing] The missing items list only listens for item data while it is open.
- [Theme] Removed the "Style of my specialization" theme. "Style of my class" stays; anyone who had the specialization theme selected is moved to it.
- [Panel] The roll history keeps the last 200 rolls (it kept 50).
- [Options] The Preview buttons of the "Bonus roll window" and "Loot spec reminder" checkboxes were removed: every preview is now on the theme rows.
- [Options] The Interface version now includes 12.1.7, so the addon is not shown as out of date.

🛠️ Fix
- [Panel] Saving items with the **Mark rolled item** bar did nothing: when the saved items completed a spec's loot pool, the automatic pool reset cleared every marked item of the boss. Saved marks are now kept, the save is double-checked for every spec and any error is printed in chat.
- [Panel] The text of the Mark bar in save mode was longer than the bar and got cut off. It is now short ("Click to save") and cannot overflow, in all 11 languages.
- [Panel] The raid boss overview showed a table full of dashes when no boss had chosen items. It now explains what to do instead.
- [Panel] Items whose data was not in the local cache showed as "Item 123456" with a broken icon. The icon now always comes from the client item tables, and the name and link are requested and filled in as soon as they arrive, in every language.
- [Panel] The "all" label of a fully obtained spec showed an empty box instead of a check mark (the game font has no such character); it now uses a check icon in all 11 languages.
- [Panel] Missing icons (spec rows, the "no items" row, the roll window and the reminder) showed a red slash instead of a question mark; they now use a valid icon.
- [Theme] In the preview window the hint line overlapped the Mark bar; the window is taller now.
- [Reminder] The text of the loot spec popup (for example the chance line) was clipped by the old dialog frame. The new layout sizes everything by its real text height, so nothing is cut in any language.

---

Version: 2.2.5
2026/10/21 Released

Fork of VoidcoreAdvisor 2.4.0 by rolferik12 (MIT license, with the author's permission). Everything below is new compared to the original.

🔮 New
- [Compatibility] Works on patch 12.1.5: the removed global item functions were replaced with their `C_Item` versions. The addon lives in its own folder (`VoidcoreAdvisorReborn`); disable the original VoidcoreAdvisor first, because both use the same saved variables (Reborn warns you if both are enabled).
- [Panel] **Mark rolled item** bar to mark by hand the items you got from a Voidcore roll that the addon did not track.
- [Voidcache Scan] `/void scan [raid 14|15|16]` reads the Voidcache of every spec to mark the items you already got from the Voidcores you spent. A one-time hint tells you about it.
- [Missing] `/void missing [14|15|16]` lists every item you still need for your loot spec, best odds first.
- [Transfer] `/void export` and `/void import` copy your marked items between characters.
- [Live Raid] The loot of The Unbinding of Kith'ix (Normal, Heroic and Mythic, every class and spec) ships with the addon, outside the season fingerprint so your obtained items are never reset. `/void liveraid` reads a new raid straight from the Adventure Guide when the built-in data does not include it yet, and a chat message names raids missing from the loot data, once per raid.
- [Bonus Roll] Redesigned window: green Roll button, red Pass button, themed frame and timer bar. Optional "Are you sure?" confirmation (on by default). A red warning, a sound and an extra line appear when only 1 item is left for your spec.
- [Theme] 22 color themes: venom green (default), void purple, arcane blue, light, fire, frost, red, one for each of the 13 classes, and "Style of my class". Choose one in the options.
- [Panel] The panel can be moved (drag the header) and resized (corner grip) and remembers both. `/void resetpanel` puts it back next to the Adventure Guide.
- [Panel] `/void panel [name]` opens the Adventure Guide on a boss or dungeon with the panel showing.
- [Overview] The raid overview shows a progress bar per boss.
- [Branding] New logo and icon.

💪 Improvement
- [Bonus Roll] Shows the real Voidcore cost reported by the roll prompt.
- [Languages] All 11 languages are complete (the original left some texts in English). The newest texts were translated without a native review: corrections are welcome.
- [Commands] The command is now `/void` (also `/voidreborn`).
- [Performance] The login item-cache warmup is gentler, to avoid frame rate dips after logging in.

🛠️ Fix
- [Detection] Voidcore rolls were not tracked when the boss selected in the Adventure Guide was not the boss that dropped the item. Rolls saved by the old version are applied again when you log in.
- [Panel] The loot spec label no longer overlaps the spec column title.

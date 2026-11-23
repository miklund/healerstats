# HealerStats

A World of Warcraft (Classic) addon to record and display stats about your healer journey.

HealerStats tracks every dungeon run you heal: whether it was completed, how many times the group wiped, and how many players died on your watch. It turns that into success statistics you can share with your group.

## Features

- Log runs by dungeon, with completion, wipe and death counts.
- The dungeon is picked up when you enter an instance; instances missing from the built-in list (`Dungeons.lua`) are added automatically.
- Wipes and deaths are tracked during the run, and you can adjust them before saving.
- Summary statistics: number of dungeons run and the percentage completed, without wipes, and without any deaths.
- View your stats on the Stats tab, post them to party or raid chat, or copy them from a popup box.

## Usage

- `/healerstats` opens or closes the run window.
- `/healerstats stats` prints your summary to chat.
- `/healerstats post` posts your summary to raid or party chat, or guild chat if you are not grouped (otherwise prints it locally).
- Typing `healerstats` in party, raid or guild chat makes the addon reply with your summary (10 second cooldown).

## Installation

Copy this folder to `World of Warcraft/_classic_/Interface/AddOns/HealerStats`.

Data is stored in the `HealerStatsDB` saved variable.

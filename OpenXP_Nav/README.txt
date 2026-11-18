OpenXP Navigation (OpenXP_Nav)
=============================

An optional helper for the OpenXP addon. With it installed, OpenXP's arrow follows
walking paths worked out ahead of time instead of pointing in a straight line.
OpenXP works without it. It only holds data: it runs no code of its own besides
filling the tables below, and it never moves, clicks or acts for the player.

What is in it
-------------
- Init.lua: makes the empty tables and sets the global OpenXP_Nav.
- Paths-Alliance.lua, Paths-Horde.lua: each guide walk as a list of corners
  (map x %, map y %, height in yards, 1 if indoors), and the floor height of each
  guide spot. Plain numbers. Each file only runs for its own faction.
- Graphs/<zone>.lua: each zone's walking network (points and the links between
  them), packed into one text string per zone to keep the download small. These
  strings are data, not code: nothing ever runs them.
- Unpack.lua: the readable Lua that turns a packed string back into a table of
  points and links. Read it to see exactly what a packed string holds.

How it was made
---------------
SoupEngine (OpenXP's route builder) walked every leg of the guides on SoupNav's
walking map and wrote the corners down. SoupNav made the zone networks. No game
files, terrain, models or textures are included, only points and links.

License: GPL-3.0, like OpenXP.

#!/usr/bin/env python3

"""Analyzes player data to determine which players are "unused"."""

import datetime
import sqlite3
import time
import pprint

min_xp = 1
min_actions = 1
login_threshold = int(time.time()) - (86400 * 90)

# Keep all playes with any of these privs.
special_privs = ["citizenship", "staff"]

# Metadata keys to keep (as integers).
meta_keys_int = [
    "crafted",
    "digged_nodes",
    "inflicted_damage",
    "placed_nodes",
    "played_time",
    "xp",
]

# Keep these players no matter what.
keep_list = ["ADMIN"]

# Where to find the database files.
PLAYERS = "players.sqlite"
AUTH = "auth.sqlite"

# Maps player data to what we know about them.
players = {}


def empty_player():
    return {
        "auth_id": 0,
        "last_login": -1,
        "creation_date": -1,
        "privs": [],
        "xp": 0,
        "digged_nodes": 0,
        "crafted": 0,
        "placed_nodes": 0,
        "inflicted_damage": 0,
        "played_time": 0,
        "actions": 0,
    }


def get_player(name):
    if name not in players:
        players[name] = empty_player()
    return players[name]


def read_auth_data():
    uri = f"file:{AUTH}?mode=ro"
    conn = sqlite3.connect(uri, uri=True)

    id_map = {}

    cursor = conn.cursor()
    cursor.execute("select id, name, last_login from auth")
    for rec in cursor.fetchall():
        id, name = rec[0], rec[1]

        id_map[id] = name
        get_player(name)["auth_id"] = id
        get_player(name)["last_login"] = rec[2]

    cursor = conn.cursor()
    cursor.execute("select id, privilege from user_privileges")
    for rec in cursor.fetchall():
        name = id_map[rec[0]]
        priv = rec[1]
        if priv in special_privs:
            get_player(name)["privs"].append(priv)


def read_player_data():
    uri = f"file:{PLAYERS}?mode=ro"
    conn = sqlite3.connect(uri, uri=True)
    cursor = conn.cursor()

    cursor.execute("select name, strftime('%s', creation_date) from player")
    for rec in cursor.fetchall():
        get_player(rec[0])["creation_date"] = int(rec[1])

    cursor.execute("select player, metadata, value from player_metadata")
    for rec in cursor.fetchall():
        name, key, value = rec[0], rec[1], rec[2]
        p = get_player(name)
        if key in meta_keys_int:
            p[key] = int(value)
        p["actions"] = (
            p["digged_nodes"]
            + p["crafted"]
            + p["placed_nodes"]
            + p["inflicted_damage"]
        )


# Return 'true' if we keep this player, 'false' if we delete them.
def keep_player(player):
    if player == "":  # Weird data that we should ignore for now.
        return True

    if player in keep_list:
        return True

    info = players[player]
    if info["xp"] >= min_xp:
        return True

    if "citizenship" in info["privs"]:
        return True

    if info["actions"] >= min_actions:
        return True

    if info["last_login"] > login_threshold:
        return True

    # Drop player if we have auth data and no player data.
    if info["auth_id"] > 0 and info["creation_date"] < 1:
        return False

    # Drop player if we have player data and no auth data.
    # This is rare.
    if info["auth_id"] < 0 and info["creation_date"] > 0:
        return False

    return False

# Return list of players to delete.
def filter_players():
    return [p for p in players if not keep_player(p)]


now = int(time.time())
read_auth_data()
read_player_data()
a = filter_players()
for name in sorted(a):
    id = players[name]["auth_id"]
    xp = players[name]["xp"]
    actions = players[name]["actions"]
    age = int((now - players[name]["last_login"]) / 86400)
    print(f"{name:30} {xp:9} {actions:11} {age:5} {id:6}")

print(f"# Total Players:  {len(players):7}")
print(f"# Unused Players: {len(a):7}")

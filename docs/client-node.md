# Setting up a DDB client node

A client node runs one service, `ddb listen`. It serves users' sessions from the node software (G8BPQ or XRouter) and polls the node's DAPPS inbox `ddb`, which every enabled source shares. Everything it needs lives in one folder, the client folder, here `~/ddb`:

| File | What it is |
|---|---|
| `ddb.pyz` | the program (from `scripts/build.sh`) |
| `ddb.env` | settings and the token, mode 600 |
| `ddb.sqlite3` | its state, created on first start |
| `descriptions/` | optional: extra data set description files (`*.json`); forecasts (`FC`) are built in |

## Before you start

The node needs these. On Debian, Ubuntu or Raspberry Pi OS, this checks them all:
```
python3 --version                                     # 3.10 or later
python3 -c 'import sqlite3; print(sqlite3.sqlite_version)'
git --version
systemctl --user status >/dev/null && echo "systemd user services OK"
```

- **Python 3.10 or later, as `python3`.** Debian 12, Ubuntu 22.04 and Raspberry Pi OS 12 (bookworm) or later have it. Debian 11 and Raspberry Pi OS 11 (bullseye) have 3.9, which is too old: upgrade the OS. If `python3` is missing, run `sudo apt install python3`. The programs bundle their one other dependency (`requests`), so there's nothing to install with `pip`.
- **SQLite.** There's nothing to install separately: the database is built into Python as its `sqlite3` module, and the database file is created on first start. The check above prints SQLite's version (3.24 or later is needed; any Python 3.10 from a distribution has a newer one). If it fails with `No module named '_sqlite3'`, this Python was built without SQLite. Use the distribution's `python3` instead. The `sqlite3` command-line tool isn't needed, though `sudo apt install sqlite3` gets it if you want to look inside the database.
- **git**, to clone and update the deployment repo: `sudo apt install git`.
- **systemd user services**, for the service to run under your own user. Every systemd distribution has them. Running at boot without a login needs `loginctl enable-linger $USER` (in the steps below).
- **A packet node with DAPPS** (0.58.1 or later, or an older installation) and its REST app interface, on this machine or one it can reach.

No time-zone data and no exact clock are needed: the server sends each forecast's local time. The clock still drives message ages, retries and the nightly check, where a few minutes' drift doesn't matter.

## Checklist

1. **The node's DAPPS app interface.** Note its URL, for example `http://10.0.3.23:5000/AppApi`.
2. **Tokens for apps `ddb` and `ddbs`, both minted on this node.** The `ddb` token lets `ddb` read and ack its one inbox, whatever the number of sources. The `ddbs` token lets it send commands to the servers' `ddbs` app: newer DAPPS releases (0.58.1 and later) require one for outbound posts, while an older installation set up before that requirement accepts them without, so the `ddbs` token can stay empty there.
3. **The forecast servers' DAPPS callsigns, in order of preference.** A server is where `ddbs` and `ddb-hub` run, usually the server node's callsign with SSID -7. One is enough; list more and the node fails over to the next if the one it uses goes quiet.
4. **The client folder.** Clone the client deployment repo (it holds a ready-built `ddb.pyz`; a project checkout works too after `scripts/build.sh`) and run, from the clone:
   ```
   scripts/install-client.sh ~/ddb
   ```
   It copies `ddb.pyz` in, creates `ddb.env` from `ddb.env.example` (mode 600) if there is none, and installs the `ddb` systemd user unit. Without either, put `ddb.pyz` and `ddb.env` in the folder yourself, and install `systemd/ddb.service` to `~/.config/systemd/user/ddb.service` with `@CLIENTDIR@` replaced by the folder's full path.
5. **Fill in `ddb.env`.** Set at least these:
   - `API_BASE_URL`: the URL from step 1.
   - `DDB_TOKEN` and `DDBS_TOKEN`: the tokens from step 2.
   - `FC_SERVERS`: the callsigns from step 3, comma-separated, most preferred first, e.g. `FC_SERVERS=GB7AAA-7,GB7BBB-7`.
   - `NODE_LISTEN=62001`: the TCP port the node software connects to. A bare port binds `127.0.0.1`. Keep it on localhost: the first line of each connection is trusted as the user's callsign. On a machine where other people have accounts, any of them could connect as any user.

   Keep the file mode 600. `ddb` warns if it isn't.
6. **Hook it into the node software.** `ddb hook` adds the `DDB` command to the node's configuration. Run it first without `--write` to see what it would add, then with `--write`; it keeps the old file as `<file>.pre-ddb` and does nothing if the hook is already there. The config file usually belongs to root, so use `sudo`:
   ```
   sudo python3 ddb.pyz hook bpq /etc/bpq32.cfg --port 62001            # LinBPQ / G8BPQ
   sudo python3 ddb.pyz hook xrouter /opt/xrouter/XROUTER.CFG --port 62001 --write   # XRouter
   ```
   The port must match `NODE_LISTEN` in `ddb.env`. Then restart the node software so it reads the new file. Neither G8BPQ nor XRouter passes the words after the command, so users type `DDB`, then `FC`.

   What it adds, if you'd rather do it by hand:
   - G8BPQ, `bpq32.cfg`: add `62001` to the Telnet port's `CMDPORT` list (for example `CMDPORT 63001 62001`). Then add an application line `APPLICATION 4,DDB,C 1 HOST 1`, where `1` is the Telnet port's number and `HOST 1` is the second `CMDPORT` entry (counting from 0). The application number and the slot depend on the node.
   - XRouter, `XROUTER.CFG`:
     ```
     APPL=8
         APPLNAME=DDB
         APPLTYPE=TCP,62001
     ENDAPPL
     ```
7. **Start it.**
   ```
   systemctl --user enable --now ddb
   loginctl enable-linger $USER    # so it starts at boot without a login
   ```
   The log is at `journalctl --user -u ddb -f`. It shows `listening on 127.0.0.1:62001`, then `ddb: polling inbox ddb every 5 s for fc`, then a summary every hour.
8. **Check it.** From the client folder:
   ```
   python3 ddb.pyz status --env-file ddb.env
   ```
   A healthy node ends with `OK` and exits 0. If the inbox has had no successful poll for 10 minutes, it ends with `STALE: …` and exits 1, so a monitor can run it. Then connect through the node as a user, type `DDB`, and check the greeting.

## Several servers

With more than one server in `FC_SERVERS` the node uses one at a time, the active one, and takes forecasts only from it.
- **While forecasts arrive** nothing extra is sent.
- **When nothing new has come for 9 hours** (1.5 × the forecasts' 6-hour validity) the node sends the server a short `PING`. Its `PONG` names the server's latest run: newer than the node holds means items went missing, and the node asks again; the same means the server's data source has stalled, and the node stays. Any reply at all shows the server is alive.
- **After 3 unanswered pings** (3 hours apart) the server is marked down and the node moves to the next one: a `SUB` per wanted locator there, and an `UNSUB` per locator to the old server.
- **Each night**, with its `LIST`, the node pings the servers above the active one; when one answers with current forecasts, it moves back.

`ddb status` shows the list with the active server marked, each server's last new data, last reply, unanswered pings, `DOWN`, last `PONG` and the last switch. To change servers by hand, edit `FC_SERVERS` and restart: an active server that is no longer listed is replaced by the first one.

## One-off forecasts

Inside FC a user can ask for a forecast without subscribing: `GET IO83lt`. If the node received one for that locator within the last 6 hours it is ready at once (`IO83lt ready: SHOW IO83lt`) and nothing goes on air; otherwise one `GET` goes to the server, however many users ask, and the answer usually arrives within seconds. A user who has left is told at their next session (`FC: IO83lt forecast ready: SHOW IO83lt`). `SHOW` lists requested locators for 6 hours. A request with no answer after `FC_GET_TIMEOUT` (1 hour) is dropped with a notice. The operator can do the same with `ddb fc get <user> <locator>`.

## Kp and space weather

The `KP` data set (built in) is a broadcast: one bulletin for everyone, updated every 3 hours, with the current Kp (and its G level when 5 or more) and NOAA's 3-day forecast: Kp by 3-hour block, and the chance of S1+ radiation storms and R1-R2 and R3+ radio blackouts. To offer it, add `kp` to `DDB_SOURCES` (e.g. `DDB_SOURCES=fc,kp`) and set `KP_SERVERS` to the servers that run the `kp` provider, then restart `ddb`. Users type `DDB`, `KP`, then `SUB` to join and `SHOW` to read it.

## Solar data

The `SOLAR` data set (built in) is a broadcast too, one bulletin every 3 hours from NOAA SWPC: the current X-ray level and solar wind (speed, Bt and Bz), estimated HF conditions by day and night for four band groups (a rule of thumb from the solar flux and Kp), the latest flare, and the last three days' 10.7 cm solar flux (SFI), sunspot number and C, M and X flare counts. To offer it, add `solar` to `DDB_SOURCES` and set `SOLAR_SERVERS` to the servers that run the `solar` provider, then restart `ddb`. Users type `DDB`, `SOLAR`, then `SUB` and `SHOW`; `INFO` explains the figures.

## Aurora

The `AURORA` data set (built in) works like forecasts, by locator: every 3 hours, from NOAA's OVATION model, the chance of aurora at the locator, the highest within 1000 km (about as far as radio aurora reaches on 6 m and 2 m), and how near the equator a 10% chance reaches on that longitude. Users can `SUB` a locator or `GET` the latest once. To offer it, add `aurora` to `DDB_SOURCES` and set `AURORA_SERVERS` to the servers that run the `aurora` provider, then restart `ddb`.

## Earthquakes

The `QUAKES` data set (built in) works like forecasts, by locator: every 3 hours, from EMSC (the European-Mediterranean Seismological Centre), the earthquakes of the last 24 hours that are M5+ anywhere or might be felt at the locator, nearest first, each with its time, magnitude, distance, direction, depth and estimated shaking at the locator (Modified Mercalli intensity). Users can `SUB` a locator or `GET` it once; `INFO` explains the figures. To offer it, add `quakes` to `DDB_SOURCES` and set `QUAKES_SERVERS` to the servers that run the `quakes` provider, then restart `ddb`.

## Tropospheric ducting

The `TROPO` data set (built in) works like forecasts, by locator and with each GFS run: for each forecast time, whether VHF/UHF conditions look `normal`, `enhanced` (super-refraction) or `ducting`, from the steepest fall of radio refractivity in the lowest 2 km and the layer it's in. Users can `SUB` a locator or `GET` it once; `INFO` explains the figures. To offer it, add `tropo` to `DDB_SOURCES` and set `TROPO_SERVERS` to the servers that run the `tropo` provider, then restart `ddb`.

## Updates over the air

Each night, with its `LIST`, the node asks the servers it uses what they offer (`CAT`). A data set it doesn't have, and can run, is fetched and installed but not enabled (it appears in `ddb sources` as `(not enabled)`). A minor update (same major version) of an installed one is fetched and used at once, without a restart. A new major version, or one needing a newer `ddb`, is never installed on its own: the installed version keeps working, and `ddb sources`/`ddb status` say `update 2.0 available: ddb describe update kp` (or `(needs core 7)`). Run `ddb describe update kp` to fetch and install it. Fetched descriptions live in `descriptions/fetched/`; a file you put in `descriptions/` yourself always wins for its data set (a pin), and deleting a fetched file undoes the update at the next restart.

## Adding a data set

A data set is a description file, not code. Put the file in `descriptions/` beside `ddb.env` (or the directory `DDB_DESCRIPTIONS` names), then:

1. **Check it.** `python3 ddb.pyz describe check descriptions/tide.json` validates it and says whether this core can run it. Add a sample item to see it as users will. For example, from a project checkout, `python3 dist/ddb.pyz describe check src/ddb/builtin/fc.json "ITEM IO83lt 20261021T0600Z 6,11.0,82.8,996.5,0.34,82.4,20.1,234.5,60,BST"` prints `13:00 BST: 11C, humidity 83%, 997hPa, rain 0.3mm, cloud 82%, wind SW 45mph`. A field-mode description's mistakes are reported with their column in the template.
2. **See it installed.** `python3 ddb.pyz sources --env-file ddb.env` lists it as `(not enabled)`, or says why it can't be enabled (for example `needs core 3, this is 2`). An installed data set does nothing until it is enabled.
3. **Enable it.** Add its name to `DDB_SOURCES` (for example `DDB_SOURCES=fc,tide`) and set its servers with `<NAME>_SERVERS` (for example `TIDE_SERVERS`). Its other settings follow the forecast ones with its own prefix (`TIDE_MAX_USER_SUBS` and so on). Then restart `ddb`.

A file with the same ID as a built-in description replaces it. A data set that is enabled but can't be used stops `ddb` with exit 2 and the reason.

## Updating

In the deployment repo clone, run `git pull && scripts/install-client.sh ~/ddb` (from a project checkout, `scripts/build.sh && scripts/install-client.sh ~/ddb`). It replaces `ddb.pyz` and restarts `ddb` if it's running. It never touches an existing `ddb.env` or the database.

## Don't

- Run `ddb run` alongside the unit, or a second `ddb listen`. `ddb listen` already does `ddb run`'s work.
- Install the server units (`scripts/install-server-units.sh`) on a client node.

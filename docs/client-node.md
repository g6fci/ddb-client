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

## DAPPS settings

`ddb` talks only to the DAPPS on its own node. DAPPS carries the messages between nodes, so it needs these, set on its dashboard (DAPPS's docs: [configure](https://github.com/packet-net/dapps/blob/master/docs/configure.md), [discovery and routing](https://github.com/packet-net/dapps/blob/master/docs/discovery-and-routing.md)):

- **DAPPS running, with its own callsign.** This is DAPPS's callsign with an SSID, not the node's: conventionally the node's callsign with `-7`, e.g. `GB7AAA-7`. The server sends forecasts to this callsign.
- **The REST app interface reachable from `ddb`.** It's on the dashboard's port, by default `http://<host>:5000`, and `ddb` uses its `/AppApi` path, e.g. `API_BASE_URL=http://127.0.0.1:5000/AppApi`.
- **Two app tokens**, from the dashboard's **App tokens** page (under System): mint one for app `ddb` and one for app `ddbs`. Each plaintext token is shown once: copy them into `ddb.env` (step 5 below) as `DDB_TOKEN` and `DDBS_TOKEN`. If the node has **Require per-app tokens** turned off, leave both empty.
- **A neighbour for the server.** DAPPS never adds neighbours by itself. On **Topology > Neighbours**, add the server's DAPPS callsign, **`GB7FCI-7`** to start with:
  - In radio range of its node, or reached over AXIP: give the radio port you'd use for `C <port> GB7FCI-7` at your node's prompt. Check it by hand first: `C <port> GB7FCI-7` should answer `DAPPSv1>`.
  - Further away: add it with a **Connect via** node and a **connect script**, as DAPPS's [multi-hop guide](https://github.com/packet-net/dapps/blob/master/docs/multi-hop.md) describes.
  - Then use **probe now** on the row to check that the link works end to end.
- **The way back.** The server sends forecasts whenever a new run arrives, not only in reply, so it has to reach your node as well. Send the server's operator your DAPPS callsign and how to connect to it (port, or the route through other nodes) so they can add you as a neighbour too. Until they do, items may wait at the server until your node next calls it.

### The server

The first server is **`GB7FCI-7`**, and it serves every data set. Put it in `DDB_SERVERS`, which every enabled data set uses. To take one data set from different servers, set that data set's own `<NAME>_SERVERS` (e.g. `KP_SERVERS=GB7BBB-7`), which wins for it alone. When more servers come up, add them after it, comma-separated, and the node fails over between them (see "Several servers" below).

## Checklist

1. **The node's DAPPS app interface.** Note its URL, for example `http://127.0.0.1:5000/AppApi` (see DAPPS settings above).
2. **Tokens for apps `ddb` and `ddbs`, both minted on this node** (DAPPS settings above). The `ddb` token lets `ddb` read and ack its one inbox, whatever the number of sources. The `ddbs` token lets it send commands to the servers' `ddbs` app: newer DAPPS releases (0.58.1 and later) require one for outbound posts, while an older installation set up before that requirement accepts them without, so the `ddbs` token can stay empty there.
3. **The servers' DAPPS callsigns, in order of preference.** Start with `GB7FCI-7`. A server is where `ddbs` and `ddb-hub` run, usually the server node's callsign with SSID -7. One is enough; list more and the node fails over to the next if the one it uses goes quiet.
4. **The client folder.** Clone the client deployment repo (it holds a ready-built `ddb.pyz`; a project checkout works too after `scripts/build.sh`) and run, from the clone:
   ```
   scripts/install-client.sh ~/ddb
   ```
   It copies `ddb.pyz` in, creates `ddb.env` from `ddb.env.example` (mode 600) if there is none, and installs the `ddb` systemd user unit. Without either, put `ddb.pyz` and `ddb.env` in the folder yourself, and install `systemd/ddb.service` to `~/.config/systemd/user/ddb.service` with `@CLIENTDIR@` replaced by the folder's full path.
5. **Fill in `ddb.env`.** Set at least these:
   - `API_BASE_URL`: the URL from step 1.
   - `DDB_TOKEN` and `DDBS_TOKEN`: the tokens from step 2.
   - `DDB_SERVERS`: the callsigns from step 3, comma-separated, most preferred first, to begin with `DDB_SERVERS=GB7FCI-7`, later e.g. `DDB_SERVERS=GB7FCI-7,GB7BBB-7`.
   - `NODE_LISTEN=62001`: the TCP port the node software connects to. A bare port binds `127.0.0.1`. Keep it on localhost: the first line of each connection is trusted as the user's callsign. On a machine where other people have accounts, any of them could connect as any user.

   Keep the file mode 600. `ddb` warns if it isn't.
6. **Hook it into the node software**, so users can type `DDB` at the node prompt. `ddb hook` adds the lines for you; see "Node software: G8BPQ and XRouter" below for what they do, doing it by hand, and checking it.
   ```
   sudo python3 ddb.pyz hook bpq /etc/bpq32.cfg --port 62001                # LinBPQ / G8BPQ
   sudo python3 ddb.pyz hook xrouter /opt/xrouter/XROUTER.CFG --port 62001  # XRouter
   ```
   That shows what it would add. Run it again with `--write` to add it, then restart the node software.
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

## Node software: G8BPQ and XRouter

Users reach `ddb` through one node command, `DDB`, whatever the number of data sets. When a user types it, the node software opens a TCP connection to `ddb listen` on this machine, at the port in `NODE_LISTEN` (62001 here). It sends the user's callsign as the first line, then passes the session through both ways. Neither G8BPQ nor XRouter passes on words typed after the command, so users type `DDB`, then `FC` (or `KP` and so on) at the DDB prompt.

Keep `NODE_LISTEN` on localhost (a bare port binds `127.0.0.1`): `ddb` trusts the first line as the user's callsign.

### `ddb hook`

`ddb hook bpq|xrouter CONFIG [--port 62001] [--write]` finds what's needed in the node's configuration file and adds it:
- **Without `--write`** it prints the lines it would add and changes nothing.
- **With `--write`** it saves the old file as `<file>.pre-ddb` (with a timestamp if that already exists), then writes the new one, keeping its owner and mode.
- **If `DDB` is already there** it does nothing.
- **It stops (exit 2)** if it can't read the file, BPQ has no Telnet port, or there's no free `APPLICATION` number.

Restart the node software afterwards: it only reads its configuration at startup. To undo, copy the `.pre-ddb` file back and restart.

### G8BPQ (LinBPQ)

BPQ reaches local TCP programs through its Telnet port: a port with `DRIVER=Telnet` lists, in its `CONFIG` block, the local TCP ports it may connect to on `CMDPORT`. An `APPLICATION` line then makes a node command that connects to one of them. In `bpq32.cfg`:

```
PORT
  PORTNUM=2
  ID=Telnet
  DRIVER=Telnet
  CONFIG
  ...                      ; the Telnet port's own settings, unchanged
  CMDPORT 62001
ENDPORT

APPLICATION 2,DDB,C 2 HOST 0
```

- `CMDPORT 62001` lists `ddb`'s port. If the line already lists others (`CMDPORT 63001`), add it at the end (`CMDPORT 63001 62001`). Don't reorder the list: other applications refer to its entries by position.
- In `APPLICATION 2,DDB,C 2 HOST 0`:
  - `2` is a free application number (1 to 32).
  - `DDB` is the command users type.
  - `C 2` connects through the Telnet port, the `2` being its `PORTNUM`.
  - `HOST 0` is the `CMDPORT` entry to connect to, counting from 0: `HOST 1` for `CMDPORT 63001 62001`.
- Restart LinBPQ.

`ddb hook bpq` works all three numbers out from the file.

### XRouter

XRouter connects to local TCP programs itself. Add an `APPL` block to `XROUTER.CFG`, with the next free `APPL` number:

```
APPL=1
	APPLNAME=DDB
	APPLTYPE=TCP,62001
ENDAPPL
```

- `APPLNAME` is the command users type.
- `APPLTYPE=TCP,62001` is `ddb`'s port on this machine.

XRouter allows only a few `APPL` blocks, which is one reason `ddb` keeps every data set behind one command. Restart XRouter.

A user who came in from another node arrives as `CALL@NODE`; `ddb` drops the `@NODE`. A console login sends its login name (e.g. `sysop`), which isn't a callsign, so `ddb` refuses it: test as a real user.

### Checking it

1. **`ddb` is listening.** With the `ddb` service running, `journalctl --user -u ddb` shows `listening on 127.0.0.1:62001`. If it isn't running, users get a failed connect from the node.
2. **It answers.** Without the node: `nc 127.0.0.1 62001`, then type a callsign (e.g. `G4ABC`) and Enter. You should get the DDB greeting. Type `BYE` to leave.
3. **Through the node.** Connect to the node as a user, type `DDB`, and check the greeting. Then try `FC`, `HELP` and `BYE`.

## Several servers

With more than one server in `DDB_SERVERS` the node uses one at a time, the active one, and takes forecasts only from it.
- **While forecasts arrive** nothing extra is sent.
- **When nothing new has come for 9 hours** (1.5 × the forecasts' 6-hour validity) the node sends the server a short `PING`. Its `PONG` names the server's latest run: newer than the node holds means items went missing, and the node asks again; the same means the server's data source has stalled, and the node stays. Any reply at all shows the server is alive.
- **After 3 unanswered pings** (3 hours apart) the server is marked down and the node moves to the next one: a `SUB` per wanted locator there, and an `UNSUB` per locator to the old server.
- **Each night**, with its `LIST`, the node pings the servers above the active one; when one answers with current forecasts, it moves back.

`ddb status` shows the list with the active server marked, each server's last new data, last reply, unanswered pings, `DOWN`, last `PONG` and the last switch. To change servers by hand, edit `DDB_SERVERS` and restart: an active server that is no longer listed is replaced by the first one.

## One-off forecasts

Inside FC a user can ask for a forecast without subscribing: `GET IO83lt`. If the node received one for that locator within the last 6 hours it is ready at once (`IO83lt ready: SHOW IO83lt`) and nothing goes on air; otherwise one `GET` goes to the server, however many users ask, and the answer usually arrives within seconds. A user who has left is told at their next session (`FC: IO83lt forecast ready: SHOW IO83lt`). `SHOW` lists requested locators for 6 hours. A request with no answer after `DDB_GET_TIMEOUT` (1 hour) is dropped with a notice. The operator can do the same with `ddb fc get <user> <locator>`.

## Kp and space weather

The `KP` data set (built in) is a broadcast: one bulletin for everyone, updated every 3 hours, with the current Kp (and its G level when 5 or more) and NOAA's 3-day forecast: Kp by 3-hour block, and the chance of S1+ radiation storms and R1-R2 and R3+ radio blackouts. To offer it, add `kp` to `DDB_SOURCES` (e.g. `DDB_SOURCES=fc,kp`) and restart `ddb`. It uses the servers in `DDB_SERVERS`; set `KP_SERVERS` only to take it from other servers that run the `kp` provider. Users type `DDB`, `KP`, then `SUB` to join and `SHOW` to read it.

## Solar data

The `SOLAR` data set (built in) is a broadcast too, one bulletin every 3 hours from NOAA SWPC: the current X-ray level and solar wind (speed, Bt and Bz), estimated HF conditions by day and night for four band groups (a rule of thumb from the solar flux and Kp), the latest flare, and the last three days' 10.7 cm solar flux (SFI), sunspot number and C, M and X flare counts. To offer it, add `solar` to `DDB_SOURCES` and restart `ddb`. It uses `DDB_SERVERS`; set `SOLAR_SERVERS` only to take it from other servers that run the `solar` provider. Users type `DDB`, `SOLAR`, then `SUB` and `SHOW`; `INFO` explains the figures.

## Aurora

The `AURORA` data set (built in) works like forecasts, by locator: every 3 hours, from NOAA's OVATION model, the chance of aurora at the locator, the highest within 1000 km (about as far as radio aurora reaches on 6 m and 2 m), and how near the equator a 10% chance reaches on that longitude. Users can `SUB` a locator or `GET` the latest once. To offer it, add `aurora` to `DDB_SOURCES` and restart `ddb`. It uses `DDB_SERVERS`; set `AURORA_SERVERS` only to take it from other servers that run the `aurora` provider.

## Earthquakes

The `QUAKES` data set (built in) works like forecasts, by locator: every 3 hours, from EMSC (the European-Mediterranean Seismological Centre), the earthquakes of the last 24 hours that are M5+ anywhere or might be felt at the locator, nearest first, each with its time, magnitude, distance, direction, depth and estimated shaking at the locator (Modified Mercalli intensity). Users can `SUB` a locator or `GET` it once; `INFO` explains the figures. To offer it, add `quakes` to `DDB_SOURCES` and restart `ddb`. It uses `DDB_SERVERS`; set `QUAKES_SERVERS` only to take it from other servers that run the `quakes` provider.

## Tropospheric ducting

The `TROPO` data set (built in) works like forecasts, by locator and with each GFS run: for each forecast time, whether VHF/UHF conditions look `normal`, `enhanced` (super-refraction) or `ducting`, from the steepest fall of radio refractivity in the lowest 2 km and the layer it's in. Users can `SUB` a locator or `GET` it once; `INFO` explains the figures. To offer it, add `tropo` to `DDB_SOURCES` and restart `ddb`. It uses `DDB_SERVERS`; set `TROPO_SERVERS` only to take it from other servers that run the `tropo` provider.

## Updates over the air

Each night, with its `LIST`, the node asks the servers it uses what they offer (`CAT`). A data set it doesn't have, and can run, is fetched and installed but not enabled (it appears in `ddb sources` as `(not enabled)`). A minor update (same major version) of an installed one is fetched and used at once, without a restart. A new major version, or one needing a newer `ddb`, is never installed on its own: the installed version keeps working, and `ddb sources`/`ddb status` say `update 2.0 available: ddb describe update kp` (or `(needs core 7)`). Run `ddb describe update kp` to fetch and install it. Fetched descriptions live in `descriptions/fetched/`; a file you put in `descriptions/` yourself always wins for its data set (a pin), and deleting a fetched file undoes the update at the next restart.

## Adding a data set

A data set is a description file, not code. Put the file in `descriptions/` beside `ddb.env` (or the directory `DDB_DESCRIPTIONS` names), then:

1. **Check it.** `python3 ddb.pyz describe check descriptions/tide.json` validates it and says whether this core can run it. Add a sample item to see it as users will. For example, from a project checkout, `python3 dist/ddb.pyz describe check src/ddb/builtin/fc.json "ITEM IO83lt 20261021T0600Z 6,11.0,82.8,996.5,0.34,82.4,20.1,234.5,60,BST"` prints `13:00 BST: 11C, humidity 83%, 997hPa, rain 0.3mm, cloud 82%, wind SW 45mph`. A field-mode description's mistakes are reported with their column in the template.
2. **See it installed.** `python3 ddb.pyz sources --env-file ddb.env` lists it as `(not enabled)`, or says why it can't be enabled (for example `needs core 3, this is 2`). An installed data set does nothing until it is enabled.
3. **Enable it.** Add its name to `DDB_SOURCES` (for example `DDB_SOURCES=fc,tide`). It uses the `DDB_*` settings (`DDB_SERVERS`, `DDB_MAX_USER_SUBS` and so on), unless you set its own with its name instead of `DDB` (`TIDE_SERVERS`, `TIDE_MAX_USER_SUBS`). Then restart `ddb`.

A file with the same ID as a built-in description replaces it. A data set that is enabled but can't be used stops `ddb` with exit 2 and the reason.

## Updating

In the deployment repo clone, run `git pull && scripts/install-client.sh ~/ddb` (from a project checkout, `scripts/build.sh && scripts/install-client.sh ~/ddb`). It replaces `ddb.pyz` and restarts `ddb` if it's running. It never touches an existing `ddb.env` or the database.

## Don't

- Run `ddb run` alongside the unit, or a second `ddb listen`. `ddb listen` already does `ddb run`'s work.
- Install the server units (`scripts/install-server-units.sh`) on a client node.

# DDB client

DDB serves data to packet-radio node users over the node's DAPPS app interface: weather forecasts by locator (`FC`), the Kp index (`KP`), solar data (`SOLAR`), aurora (`AURORA`), earthquakes (`QUAKES`) and tropospheric ducting (`TROPO`), all under one node command, `DDB`.

This repo holds what a client node needs, ready built:

| File | What it is |
|---|---|
| `ddb.pyz` | the program: one file, runs on any Python 3.10 or later |
| `ddb.env.example` | the settings template |
| `systemd/ddb.service` | the systemd user unit |
| `scripts/install-client.sh` | sets up or updates a client folder |
| `docs/client-node.md` | the full setup guide |
| `VERSION` | the build this is |

## Install

```
git clone <this repo> ~/ddb-client
cd ~/ddb-client
scripts/install-client.sh ~/ddb
```

Then fill in `~/ddb/ddb.env`, hook `DDB` into the node software and start the service: steps 6 to 9 of [docs/client-node.md](docs/client-node.md).

## Update

```
cd ~/ddb-client && git pull && scripts/install-client.sh ~/ddb
```

It replaces `ddb.pyz` and restarts `ddb` if it's running; `ddb.env` and the database are never touched.

This repo is generated from the development repo; changes made here are overwritten by the next release.

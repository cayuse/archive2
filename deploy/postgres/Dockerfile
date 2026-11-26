# The Archive's Postgres: the official image plus pglogical, which keeps peers' databases in step
# both ways (docs/PEERS.md). Same major version as production (15); bump both together.
FROM postgres:15-trixie
RUN apt-get update \
 && apt-get install -y --no-install-recommends postgresql-15-pglogical \
 && rm -rf /var/lib/apt/lists/*
# Settings a peer needs (wal_level, pglogical, commit timestamps for last-update-wins) are passed
# on the command line by whatever runs the container (Kamal accessory, docker compose), so the
# same image also runs as a plain single database.

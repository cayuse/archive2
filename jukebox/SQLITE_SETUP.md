# SQLite3 Setup for Jukebox

## Problem
The jukebox app is configured to use SQLite3, but PostgreSQL environment variables are set globally in the devcontainer configuration, which causes Rails to try to use PostgreSQL instead of SQLite3.

## Solution
Use the provided wrapper scripts that automatically unset PostgreSQL environment variables.

## Available Scripts

### `./bin/rails-sqlite`
A wrapper for Rails commands that automatically unsets PostgreSQL environment variables.

**Usage:**
```bash
# Instead of: ./bin/rails db:create
./bin/rails-sqlite db:create

# Instead of: ./bin/rails db:migrate
./bin/rails-sqlite db:migrate

# Instead of: ./bin/rails console
./bin/rails-sqlite console

# Instead of: ./bin/rails server
./bin/rails-sqlite server
```

### `./bin/setup-sqlite`
A general-purpose script to unset PostgreSQL environment variables and execute any command.

**Usage:**
```bash
./bin/setup-sqlite your-command-here
```

## Manual Solution
If you prefer to manually unset the environment variables:

```bash
unset POSTGRES_HOST POSTGRES_USER POSTGRES_PASSWORD POSTGRES_PORT
./bin/rails db:create
```

## Database Configuration
The app is configured to use SQLite3 with the following databases:
- Development: `db/development.sqlite3`
- Test: `db/test.sqlite3`
- Production: `db/production.sqlite3`

## Why This Happens
The devcontainer configuration sets PostgreSQL environment variables globally for the archive app, but these variables interfere with the jukebox app's SQLite3 configuration. When these variables are present, Rails automatically tries to use PostgreSQL instead of the SQLite3 configuration in `config/database.yml`. 
#!/usr/bin/env python3
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    """
    Application configuration model.
    Loads settings from environment variables and a .env file.
    """
    model_config = SettingsConfigDict(
        env_file='.env',
        env_file_encoding='utf-8',
        env_prefix='PLAYER_'  # Looks for environment variables like PLAYER_REDIS_HOST
    )

    # Redis Configuration
    # Maps to PLAYER_REDIS_HOST from env
    REDIS_HOST: str = "localhost"
    REDIS_PORT: int = 6379
    REDIS_DB: int = 1

    # Jukebox API
    API_URL: str = "http://localhost:3001/api"

    # MPV Player Settings
    VOLUME: int = 80
    MPV_SOCKET: str = "/tmp/player_mpv.sock"
    CACHE_SECS: int = 20

    # Redis Keys
    STATUS_KEY: str = "player:status"
    CMD_LIST: str = "player:commands"
    CUR_SONG: str = "player:current_song"
    DESIRED: str = "player:desired_state"

# Create a single, importable instance of the settings
settings = Settings()
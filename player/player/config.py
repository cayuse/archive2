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
    STATUS_KEY: str = "jukebox:player_status"
    CMD_LIST: str = "jukebox:commands"
    CUR_SONG: str = "jukebox:current_song"
    DESIRED: str = "jukebox:desired_state"

    def patch_stream_url(self, stream_url: str) -> str:
        """
        For localhost deployment, just return the original stream URL as-is.
        No URL patching needed when API and player are on same system.
        
        Note: The original complex URL patching logic was removed for localhost
        deployments as it's unnecessary when the API and player run on the same system.
        """
        return stream_url

# Create a single, importable instance of the settings
settings = Settings()
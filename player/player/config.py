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
        Replace the base URL portion of a stream URL with the configured API_URL.
        
        Example:
        Input: 'http://localhost:3001/api/jukebox/player/stream/723ca04e-5f41-4764-8b75-7703ae03c099.flac'
        Output: 'http://localhost:3011/api/jukebox/player/stream/723ca04e-5f41-4764-8b75-7703ae03c099.flac'
        """
        if not stream_url:
            return stream_url
            
        # Find the position of '/api' in the URL
        api_index = stream_url.find('/api')
        if api_index == -1:
            # If '/api' is not found, return the original URL
            return stream_url
        
        # Extract the path starting from '/api'
        api_path = stream_url[api_index:]
        
        # Combine with the configured API_URL
        # Remove '/api' from API_URL if it exists to avoid duplication
        base_url = self.API_URL.rstrip('/api').rstrip('/')
        
        return f"{base_url}{api_path}"

# Create a single, importable instance of the settings
settings = Settings()
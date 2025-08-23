#!/usr/bin/env python3
import sys, signal, logging
from .player_logic import Player

def setup_logging():
    """Configures root logger for the application."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        stream=sys.stdout,
    )

def main():
    """Initializes and runs the Player, handling graceful shutdown."""
    setup_logging()
    log = logging.getLogger("player.main")

    try:
        app = Player()
    except RuntimeError as e:
        log.critical(f"Failed to initialize Player: {e}")
        sys.exit(1)

    def signal_handler(sig, frame):
        log.info(f"Caught signal {sig}, initiating shutdown...")
        app.shutdown()

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    try:
        app.run()
    except Exception as e:
        log.critical(f"An unhandled exception occurred: {e}", exc_info=True)
        app.shutdown()
        sys.exit(1)

    log.info("Player has shut down.")
    sys.exit(0)

if __name__ == "__main__":
    main()
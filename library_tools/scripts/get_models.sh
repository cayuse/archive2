#!/usr/bin/env bash
# Download the Essentia models used by analyze_audio.py (CC BY-NC-SA 4.0, fine for personal use).
# Usage: bash get_models.sh <models_dir>
set -euo pipefail
cd "${1:?models dir}"
B=https://essentia.upf.edu/models
get() { for ext in pb json; do [ -s "$(basename "$1").$ext" ] || curl -fsSL -O "$B/$1.$ext"; done; }
get feature-extractors/discogs-effnet/discogs-effnet-bs64-1
get classification-heads/genre_discogs400/genre_discogs400-discogs-effnet-1
for m in mood_happy mood_sad mood_aggressive mood_relaxed mood_party mood_acoustic mood_electronic danceability voice_instrumental; do
  get classification-heads/$m/$m-discogs-effnet-1
done
get classification-heads/approachability/approachability_regression-discogs-effnet-1
get classification-heads/engagement/engagement_regression-discogs-effnet-1
get tempo/tempocnn/deeptemp-k16-3
ls -la

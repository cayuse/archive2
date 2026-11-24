#!/usr/bin/env bash
# One-off: generate the audio-analysis models with the Rails generators.
# Run:  bash rails.sh bash /work/scripts/gen_audio_tables.sh
set -euo pipefail
bundle exec rails g model SongAudioFeature song:references analysis_model:string \
  analyzed_seconds:float loudness_db:float peak_db:float tempo_bpm:float brightness_hz:float onset_strength:float \
  energy:float danceability:float happiness:float aggression:float acousticness:float electronic:float \
  instrumental:float speech:float analyzed_at:datetime --no-fixture
sleep 1
bundle exec rails g model SongEmbedding song:references analysis_model:string dimensions:integer --no-fixture
sleep 1
bundle exec rails g model SongNeighbor song:references neighbor:references rank:integer score:float --no-fixture

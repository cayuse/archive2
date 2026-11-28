# The audio checkers the library audit uses. Debian's packaged tools only: no AI, no network services.
FROM debian:trixie-slim
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
      ffmpeg mp3val flac libchromaprint-tools python3 python3-numpy python3-scipy \
      openssh-client ca-certificates && rm -rf /var/lib/apt/lists/* \
 && useradd -u 1000 -m audit
USER audit
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 PYTHONUNBUFFERED=1

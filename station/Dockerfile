# The archive node's player daemon (station.py): follows the archive, feeds OwnTone.
# Standard library only, so the image is just Python plus two files.
FROM python:3.15-alpine
LABEL service="archive-player"
RUN adduser -D -u 1000 player && mkdir /data && chown player /data
WORKDIR /app
COPY station.py index.html ./
ENV PYTHONUNBUFFERED=1 \
    STATE_FILE=/data/station_state.json \
    BIND_HOST=0.0.0.0 \
    BIND_PORT=8337
USER player
VOLUME /data
EXPOSE 8337
HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=3 \
  CMD python -c "import os,urllib.request; urllib.request.urlopen('http://127.0.0.1:%s/up' % os.environ.get('BIND_PORT','8337'), timeout=3)"
CMD ["python", "station.py"]

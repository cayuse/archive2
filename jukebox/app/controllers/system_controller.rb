class SystemController < ApplicationController
  before_action :set_redis

  def index
    # lightweight status fetch from Redis
    @status = begin
      raw = @redis.get('jukebox:status')
      raw ? JSON.parse(raw) : { 'state' => 'unknown' }
    rescue
      { 'state' => 'unknown' }
    end
    @current_song = begin
      raw = @redis.get('jukebox:current_song')
      raw ? JSON.parse(raw) : nil
    rescue
      nil
    end
  end

  def play
    enqueue_command(action: 'play')
    redirect_to system_path, notice: 'Play requested'
  end

  def pause
    enqueue_command(action: 'pause')
    redirect_to system_path, notice: 'Pause requested'
  end

  def stop
    enqueue_command(action: 'stop')
    redirect_to system_path, notice: 'Stop requested'
  end

  def next
    enqueue_command(action: 'next')
    redirect_to system_path, notice: 'Skip requested'
  end

  private

  def set_redis
    url = ENV['REDIS_URL']
    if url.present?
      @redis = Redis.new(url: url)
    else
      host = ENV.fetch('REDIS_HOST', 'localhost')
      port = ENV.fetch('REDIS_PORT', '6379').to_i
      db   = ENV.fetch('REDIS_DB', '1').to_i
      @redis = Redis.new(host: host, port: port, db: db)
    end
  end

  def enqueue_command(payload)
    @redis.rpush('jukebox:commands', payload.to_json)
  end
end



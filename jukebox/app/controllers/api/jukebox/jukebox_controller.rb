module Api
  module Jukebox
    class JukeboxController < ApplicationController
      protect_from_forgery with: :null_session
      skip_before_action :verify_authenticity_token
      before_action :set_jukebox_service

      def status
        render json: @jukebox_service.status
      end

      def health
        render json: @jukebox_service.health
      end

      def sync_status
        render json: PowerSyncService.instance.sync_status
      end

      def force_sync
        PowerSyncService.instance.force_sync
        render json: { message: 'Sync forced successfully' }
      end

      def queue
        render json: {
          items: @jukebox_service.queue.map(&:as_json),
          length: @jukebox_service.queue.count
        }
      end

      def add_to_queue
        song_id = params[:song_id] || params.dig(:jukebox, :song_id)
        unless song_id
          render json: { error: 'song_id is required' }, status: :bad_request and return
        end
        begin
          priority = params[:priority] == 'head' ? 'head' : 'tail'
          queue_item = @jukebox_service.add_to_queue(song_id, priority: priority)
          render json: { message: 'Song added to queue', queue_item: queue_item.as_json }
        rescue ActiveRecord::RecordNotFound
          render json: { error: 'Song not found' }, status: :not_found
        rescue => e
          render json: { error: e.message }, status: :internal_server_error
        end
      end

      def remove_from_queue
        position = params[:position]&.to_i
        unless position
          render json: { error: 'position is required' }, status: :bad_request and return
        end
        if @jukebox_service.remove_from_queue(position)
          render json: { message: 'Song removed from queue' }
        else
          render json: { error: 'Song not found in queue' }, status: :not_found
        end
      end

      def clear_queue
        @jukebox_service.clear_queue
        render json: { message: 'Queue cleared' }
      end

      def play
        @jukebox_service.play
        render json: { message: 'Play command sent' }
      end

      def pause
        @jukebox_service.pause
        render json: { message: 'Pause command sent' }
      end

      def skip
        @jukebox_service.skip
        render json: { message: 'Skip command sent' }
      end

      def set_volume
        volume = params[:volume]&.to_i
        unless volume && volume.between?(0, 100)
          render json: { error: 'Volume must be between 0 and 100' }, status: :bad_request and return
        end
        @jukebox_service.set_volume(volume)
        render json: { message: "Volume set to #{volume}" }
      end

      # GET /api/jukebox/player/stream/:id(.:format)
      # Always return actual audio bytes (prefer local file; otherwise stream from blob)
      def stream
        # Use Song for Active Storage attachment because blobs were attached to record_type 'Song' in Archive
        song = Song.find(params[:id])
        unless song.audio_file.attached?
          head :not_found and return
        end
        # Derive content type and filename extension
        ext = song.audio_file.filename&.extension
        ctype = song.audio_file.content_type.presence
        # Fallbacks
        ext ||= File.extname(song.try(:file_path).to_s).delete_prefix('.')
        ctype ||= content_type_from_extension(ext) if ext.present?
        ctype ||= 'application/octet-stream'
        # Prefer local path if accessible
        path = JukeboxService.instance.send(:resolve_local_audio_path, song)
        if path && File.exist?(path)
          filename = ext.present? ? "#{song.id}.#{ext}" : song.id.to_s
          send_file path, type: ctype, disposition: 'inline', filename: filename
        else
          # Fallback: stream bytes directly from Active Storage
          data = song.audio_file.download
          filename = ext.present? ? "#{song.id}.#{ext}" : song.id.to_s
          send_data data, type: ctype, disposition: 'inline', filename: filename
        end
      end

      # GET /api/jukebox/player/next
      # Returns the next song to play and consumes it from the queue
      def next_song
        # 0) Ensure queue is refilled to target if below minimum
        ensure_min_queue_length!

        # 1) Consume from unified ordered queue: manual first, then random; each by position
        if (item = JukeboxQueueItem.includes(song: [:artist, :album]).ordered_for_playback.first)
          song = item.song
          source = (item.status.to_s == '1' || item.status == 'pending_random') ? 'random' : 'queue'
          item.destroy!  # remove from queue upon consumption
          JukeboxPlayedSong.create!(song_id: song.id, played_at: Time.current, source: source)
          render json: build_song_payload(song) and return
        end

        # 2) Queue is still empty after refill -> no content
        head :no_content
      end

      private
      def ensure_min_queue_length!
        min_len = SystemSetting.min_queue_length
        target  = SystemSetting.refill_queue_to
        return if min_len <= 0 || target <= 0
        current = JukeboxQueueItem.count
        return if current >= min_len

        need = [target - current, 0].max
        return if need <= 0

        # Get selected playlist IDs
        selected_ids = JukeboxSelectedPlaylist.pluck(:playlist_id)
        
        # If no playlists are selected, don't add any random songs
        if selected_ids.empty?
          Rails.logger.warn "No playlists selected for jukebox - cannot add random songs"
          return
        end

        # Get songs from selected playlists only
        playlist_song_ids = PlaylistsSong.where(playlist_id: selected_ids).pluck(:song_id)
        
        if playlist_song_ids.empty?
          Rails.logger.warn "Selected playlists contain no songs - cannot add random songs"
          return
        end

        # Exclude recently played and already queued songs
        recent_ids = JukeboxPlayedSong.order(played_at: :desc).limit(SystemSetting.recently_played_window).pluck(:song_id)
        queued_ids = JukeboxQueueItem.where(status: ['0','1']).pluck(:song_id)
        attached_ids = ActiveStorage::Attachment.where(record_type: 'Song', name: 'audio_file').pluck(:record_id)
        
        # First try: songs from selected playlists that haven't been played recently and aren't already queued
        available_songs = ArchiveSong.completed
                                    .where(id: attached_ids)
                                    .where(id: playlist_song_ids)
                                    .where.not(id: recent_ids + queued_ids)
                                    .order('RANDOM()')
                                    .limit(need)
        
        added = 0
        available_songs.pluck(:id).each do |sid|
          JukeboxQueueItem.add_random_to_queue(sid)
          added += 1
        end

        # If we still need more songs, allow repeats from selected playlists
        remaining = need - added
        if remaining > 0
          Rails.logger.info "Adding #{remaining} repeated songs from selected playlists to meet minimum queue length"
          
          # Get all songs from selected playlists (including repeats)
          repeat_songs = ArchiveSong.completed
                                   .where(id: attached_ids)
                                   .where(id: playlist_song_ids)
                                   .where.not(id: queued_ids) # Still exclude already queued
                                   .order('RANDOM()')
                                   .limit(remaining)
          
          repeat_songs.pluck(:id).each do |sid|
            JukeboxQueueItem.add_random_to_queue(sid)
          end
        end
      end

      def build_song_payload(song)
        host = ENV.fetch('JUKEBOX_PUBLIC_URL', 'http://localhost:3001')

        # Look up attachment directly to ensure we get real filename/content type
        att = ActiveStorage::Attachment.find_by(record_type: 'Song', name: 'audio_file', record_id: song.id)
        content_type = att&.content_type
        ext = att&.filename&.extension
        if ext.blank?
          # try from file_path column if present
          ext = File.extname(Song.find_by(id: song.id)&.file_path.to_s).delete_prefix('.')
        end
        if content_type.blank? && ext.present?
          content_type = content_type_from_extension(ext)
        end

        stream_url = if ext.present?
          Rails.application.routes.url_helpers.url_for(
            controller: '/api/jukebox/jukebox', action: 'stream', id: song.id, host: host, format: ext
          )
        else
          Rails.application.routes.url_helpers.url_for(
            controller: '/api/jukebox/jukebox', action: 'stream', id: song.id, host: host
          )
        end

        {
          id: song.id,
          title: song.title,
          artist: song.respond_to?(:artist) ? song.artist&.name : nil,
          album: song.respond_to?(:album) ? song.album&.title : nil,
          duration: song.duration,
          cached_path: JukeboxService.instance.send(:resolve_local_audio_path, song),
          stream_url: stream_url,
          content_type: content_type
        }
      end

      def extension_from_content_type(ctype)
        case ctype
        when 'audio/mpeg' then 'mp3'
        when 'audio/flac', 'audio/x-flac' then 'flac'
        when 'audio/wav', 'audio/x-wav' then 'wav'
        when 'audio/ogg' then 'ogg'
        when 'audio/mp4', 'audio/aac', 'audio/x-m4a' then 'm4a'
        else
          ''
        end
      end

      def content_type_from_extension(ext)
        return nil if ext.blank?
        e = ext.to_s.downcase.delete_prefix('.')
        case e
        when 'mp3' then 'audio/mpeg'
        when 'flac' then 'audio/flac'
        when 'wav' then 'audio/wav'
        when 'ogg' then 'audio/ogg'
        when 'm4a' then 'audio/mp4'
        when 'aac' then 'audio/aac'
        else
          nil
        end
      end

      def ensure_random_pool!
        min_size = SystemSetting.min_random_queue_size
        # count current pool via playlists_songs table and selected playlists
        selected_ids = JukeboxSelectedPlaylist.pluck(:playlist_id)
        return if selected_ids.empty?
        # Build candidate pool: all songs in selected playlists excluding recently played
        recent_ids = JukeboxPlayedSong.order(played_at: :desc).limit(SystemSetting.recently_played_window).pluck(:song_id)
        candidate_ids = PlaylistsSong.where(playlist_id: selected_ids).where.not(song_id: recent_ids).pluck(:song_id).uniq
        # Determine how many to add; we don't persist a random queue table yet, so just ensure we have candidates
        # No-op here because we select randomly on demand in next_random_from_pool
      end

      def next_random_from_pool
        selected_ids = JukeboxSelectedPlaylist.pluck(:playlist_id)
        return nil if selected_ids.empty?
        recent_ids = JukeboxPlayedSong.order(played_at: :desc).limit(SystemSetting.recently_played_window).pluck(:song_id)
        attached_ids = ActiveStorage::Attachment.where(record_type: 'Song', name: 'audio_file').limit(10_000).pluck(:record_id)
        candidate_ids = PlaylistsSong.where(playlist_id: selected_ids)
                                     .where.not(song_id: recent_ids)
                                     .where(song_id: attached_ids)
                                     .pluck(:song_id).uniq
        return nil if candidate_ids.empty?
        ArchiveSong.where(id: candidate_ids).order('RANDOM()').first
      end

      def fallback_random_song
        # Only pick songs from selected playlists, never from anywhere in the archive
        selected_ids = JukeboxSelectedPlaylist.pluck(:playlist_id)
        if selected_ids.empty?
          Rails.logger.warn "No playlists selected for jukebox - cannot get fallback random song"
          return nil
        end
        
        recent_ids = JukeboxPlayedSong.order(played_at: :desc).limit(SystemSetting.recently_played_window).pluck(:song_id)
        attached_ids = ActiveStorage::Attachment.where(record_type: 'Song', name: 'audio_file').limit(10_000).pluck(:record_id)
        
        # Get songs from selected playlists only
        playlist_song_ids = PlaylistsSong.where(playlist_id: selected_ids).pluck(:song_id)
        if playlist_song_ids.empty?
          Rails.logger.warn "Selected playlists contain no songs - cannot get fallback random song"
          return nil
        end
        
        ArchiveSong.completed
                   .where(id: attached_ids)
                   .where(id: playlist_song_ids)
                   .where.not(id: recent_ids)
                   .order('RANDOM()')
                   .first
      end

      def cache_status
        cached_songs = @jukebox_service.cached_songs
        uncached_songs = @jukebox_service.uncached_songs
        render json: {
          cached_count: cached_songs.count,
          uncached_count: uncached_songs.count,
          total_songs: Song.count,
          cache_percentage: Song.count > 0 ? (cached_songs.count.to_f / Song.count * 100).round(1) : 0
        }
      end

      def cache_song
        song_id = params[:song_id]
        unless song_id
          render json: { error: 'song_id is required' }, status: :bad_request and return
        end
        begin
          @jukebox_service.cache_song(song_id)
          render json: { message: 'Song queued for caching' }
        rescue ActiveRecord::RecordNotFound
          render json: { error: 'Song not found' }, status: :not_found
        end
      end

      def clear_cache
        @jukebox_service.clear_cache
        render json: { message: 'Cache cleared' }
      end

      private

      def set_jukebox_service
        @jukebox_service = JukeboxService.instance
      end
    end
  end
end



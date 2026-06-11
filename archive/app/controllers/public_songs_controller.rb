class PublicSongsController < ApplicationController
  # Public, tokenized song playback. No account or login required: access is
  # granted *solely* by a signed, expiring token minted on a song's show page
  # (see SongsController#show / the share-link UI).
  #
  # The token is a Rails signed_id — an HMAC-signed blob (signed with
  # secret_key_base) carrying the song's id, a :play purpose, and an expiry. It
  # can't be forged or repurposed, it self-expires, and each link exposes exactly
  # one song. Nothing is persisted; there's no table and no link to revoke (rotate
  # secret_key_base to invalidate every outstanding token at once).

  # GET /s/:token
  def play
    song = Song.find_signed(params[:token], purpose: :play)

    unless song&.audio_file&.attached?
      # find_signed returns nil for a tampered/expired token; cover the
      # detached-file case too. Deliberately vague — don't reveal which.
      return render plain: "This play link is invalid or has expired.", status: :not_found
    end

    stream_inline(song.audio_file)
  end

  private

  # Stream the attachment inline (disposition: "inline" so browsers play it in
  # their built-in audio player instead of forcing a download) and honour HTTP
  # Range requests for seeking + iOS/Safari. Mirrors Api::V1::SongsController#stream.
  def stream_inline(attachment)
    data = attachment.download
    file_size = data.bytesize
    range = request.headers["Range"]

    if range && range =~ /bytes=(\d+)-(\d*)/
      start_byte = $1.to_i
      end_byte   = $2.empty? ? file_size - 1 : [$2.to_i, file_size - 1].min
      start_byte = 0 if start_byte >= file_size
      response.headers["Content-Range"] = "bytes #{start_byte}-#{end_byte}/#{file_size}"
      response.headers["Accept-Ranges"] = "bytes"
      send_data data.byteslice(start_byte, end_byte - start_byte + 1),
                status: :partial_content,
                type: attachment.content_type,
                disposition: "inline"
    else
      response.headers["Accept-Ranges"] = "bytes"
      send_data data, type: attachment.content_type, disposition: "inline"
    end
  end
end

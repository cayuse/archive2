require "openssl"
require "base64"

# Compact, stateless, signed play tokens for the public /s/:token song links.
#
# Rails' signed_id works but is ~250 chars (JSON + ISO timestamp + a 36-char UUID
# string + hex signature, all Base64'd). This packs the same facts into 30 bytes
# -> a 40-char URL-safe string:
#
#   bytes  0..15  song UUID, raw    (dashes stripped, hex-decoded to 16 bytes)
#   bytes 16..19  expiry            (unix epoch seconds, 32-bit big-endian)
#   bytes 20..29  signature         (HMAC-SHA256 over bytes 0..19, truncated to 10)
#
# The 30-byte blob is Base64-urlsafe encoded = exactly 40 chars, no padding.
#
# Base64 is ONLY transport encoding (URL-safety) and is fully reversible — it is
# the HMAC that makes the token unforgeable. Changing the song id or expiry alters
# bytes 0..19, so the recomputed HMAC won't match the appended signature and
# #verify returns nil. Stateless: nothing is stored, tokens self-expire, and
# bumping PURPOSE's version suffix invalidates every outstanding token at once.
module SongPlayToken
  SIG_BYTES = 10               # 80-bit tag; forging needs ~2**80 *online* guesses
  BODY_BYTES = 20              # 16 (uuid) + 4 (expiry)
  PURPOSE = "song/play/v1"     # key-derivation salt; bump "v1" to hard-invalidate all

  module_function

  # song_id: the Song UUID string. expires_in: an ActiveSupport::Duration (e.g. 5.days).
  def generate(song_id, expires_in:)
    body = pack_body(song_id, Time.now.to_i + expires_in.to_i)
    Base64.urlsafe_encode64(body + sign(body), padding: false)
  end

  # Returns the song UUID string if the token is well-formed, untampered, and
  # unexpired; otherwise nil.
  def verify(token)
    return nil if token.blank?

    blob = decode(token)
    return nil unless blob && blob.bytesize == BODY_BYTES + SIG_BYTES

    body = blob.byteslice(0, BODY_BYTES)
    sig  = blob.byteslice(BODY_BYTES, SIG_BYTES)
    return nil unless ActiveSupport::SecurityUtils.secure_compare(sig, sign(body))

    exp = body.byteslice(16, 4).unpack1("N")
    return nil if Time.now.to_i > exp

    unpack_uuid(body.byteslice(0, 16))
  end

  # --- internals ---

  def pack_body(song_id, exp)
    [song_id.to_s.delete("-")].pack("H*") + [exp].pack("N")
  end

  def unpack_uuid(raw16)
    h = raw16.unpack1("H*")
    "#{h[0, 8]}-#{h[8, 4]}-#{h[12, 4]}-#{h[16, 4]}-#{h[20, 12]}"
  end

  def sign(body)
    OpenSSL::HMAC.digest("SHA256", secret, body).byteslice(0, SIG_BYTES)
  end

  # Derived from secret_key_base via the app key generator: stable across
  # restarts/hosts, and namespaced so it never collides with other signing uses.
  def secret
    Rails.application.key_generator.generate_key(PURPOSE, 32)
  end

  def decode(token)
    Base64.urlsafe_decode64(token)
  rescue ArgumentError
    nil
  end
end

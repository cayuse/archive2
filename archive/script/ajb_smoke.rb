# AJB API smoke test against a running dev server. Usage: ruby script/ajb_smoke.rb [base_url]
require "net/http"
require "json"
require "uri"

BASE = URI(ARGV[0] || "http://localhost:3000")

def call(method, path, auth: nil, body: nil)
  req = Net::HTTP.const_get(method).new(path)
  req["Authorization"] = "Bearer #{auth}" if auth
  if body
    req["Content-Type"] = "application/json"
    req.body = body.to_json
  end
  Net::HTTP.start(BASE.host, BASE.port) { |http| http.request(req) }
end

def json(res)
  JSON.parse(res.body)
rescue StandardError
  res.body.to_s[0, 200]
end

30.times { break if (call(:Get, "/up").code == "200" rescue false); sleep 1 }

login = call(:Post, "/api/v1/auth/login", body: { email: "admin@musicarchive.com", password: "admin123" })
auth = json(login).then { |j| j["api_token"] || j.dig("data", "api_token") }
puts "login: #{login.code} auth=#{auth ? 'yes' : 'NO'}"

list = call(:Get, "/api/v1/jukeboxes", auth: auth)
puts "jukeboxes: #{list.code} #{list.body[0, 300]}"
id = list.body[/[0-9a-f]{8}-[0-9a-f-]{27}/]

3.times do
  nxt = call(:Get, "/api/v1/jukeboxes/#{id}/next_song", auth: auth)
  puts "next_song: #{nxt.code} #{nxt.body.to_s[0, 260]}"
  song_id = nxt.body.to_s[%r{songs/([0-9a-f-]{36})}, 1]
  next unless song_id
  stream = call(:Get, "/api/v1/songs/#{song_id}/stream", auth: auth)
  puts "  stream: #{stream.code} #{stream['Content-Type']} #{stream.body.bytesize} bytes"
end

queue = call(:Get, "/api/v1/jukeboxes/#{id}/queue", auth: auth)
puts "queue: #{queue.code} #{queue.body[0, 200]}"
beat = call(:Post, "/api/v1/jukeboxes/#{id}/playback_status", auth: auth,
            body: { is_playing: true, position: 1, volume: 0.8, event: "smoke" })
puts "playback_status: #{beat.code} #{beat.body.to_s[0, 150]}"
status = call(:Get, "/api/v1/jukeboxes/#{id}/status", auth: auth)
puts "status: #{status.code} #{status.body[0, 250]}"
puts "guest queue: #{call(:Get, "/api/v1/guest/#{id}/queue?password=guest").code}"
puts "player page without session: #{call(:Get, "/jukeboxes/#{id}/player").code}"

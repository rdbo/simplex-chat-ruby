require 'net/http'
require 'logger'
require_relative '../lib/simplex-chat'

puts 'Hello'


client = SimpleXChat::ClientAgent.new URI('ws://localhost:5225'), log_level: Logger::DEBUG
version = client.api_version
profile = client.api_profile
address = client.api_get_user_address || client.api_create_user_address
client.send_command '/profile'
puts "==================================="
puts
puts
puts "SimpleX Chat version: #{version}"
puts "Name: #{profile['name']}"
puts "Address: #{address}"
puts "Preferences:"
profile["preferences"].each { |k, v| puts "  - #{k} => #{v && 'yes' || 'no'}"}
puts
puts
puts "==================================="

# resp = client.api_send_text_message SimpleXChat::ChatType::DIRECT, "dummerino_1", "HELLO"
# puts "------------------------------------"
# puts "Send text message response: #{resp}"
# puts "------------------------------------"

puts "Listening for messages..."
loop do
  msg = client.next_message
  puts "Received message"
  # puts "RECEIVED MESSAGE: #{msg}"
end

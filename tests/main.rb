require 'net/http'
require 'logger'
require_relative '../lib/simplex-chat'

puts 'Hello'


client = SimpleXChat::ClientAgent.new URI('ws://localhost:5225'), log_level: Logger::DEBUG
version = client.send_command '/version'
puts "==================================="
puts
puts
puts "SimpleX Chat version: #{version["versionInfo"]["version"]}"
puts
puts
puts "==================================="

resp = client.api_send_text_message SimpleXChat::ChatType::DIRECT, "dummerino_1", "HELLO"
puts "------------------------------------"
puts "Send text message response: #{resp}"
puts "------------------------------------"

puts "Listening for messages..."
loop do
  msg = client.next_message
  puts "RECEIVED MESSAGE: #{msg}"
end

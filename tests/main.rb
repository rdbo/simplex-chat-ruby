require 'net/http'
require 'logger'
require_relative '../lib/simplex-chat'

puts 'Hello'


client = SimpleXChat::ClientAgent.new URI('ws://localhost:5225'), log_level: Logger::DEBUG
loop do
  msg = client.next_message
  puts "RECEIVED MESSAGE: #{msg}"
end

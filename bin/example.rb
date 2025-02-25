require 'net/http'
require 'logger'
require_relative '../lib/simplex-chat'

puts "Connecting client..."
client = SimpleXChat::ClientAgent.new URI('ws://localhost:5225') # , log_level: Logger::DEBUG

puts "Sending commands..."
version = client.api_version
profile = client.api_profile
address = client.api_get_user_address || client.api_create_user_address
contacts = client.api_contacts
groups = client.api_groups
client.api_auto_accept true

puts "==================================="
puts
puts
puts "SimpleX Chat version: #{version}"
puts "Name: #{profile['name']}"
puts "Address: #{address}"
puts "Preferences:"
profile["preferences"].each { |k, v| puts "  - #{k} => #{v && 'yes' || 'no'}"}
puts "Contacts:"
contacts.each { |c| puts "  - #{c['name']} (#{c['id']}) -> #{c['mergedPreferences'].map{|k, v| "#{k}: #{v}"}.join ', '}"}
puts "Groups:"
groups.each { |g| puts "  - #{g['name']} (#{g['id']}) -> alias: #{g['memberName']}, role: #{g['memberRole']}, members: #{g['currentMembers']}" }
puts
puts
puts "==================================="

puts "Listening for messages..."
loop do
  chat_msg = client.next_chat_message
  if chat_msg == nil
    puts "Message queue is closed"
    break
  end
  puts "Chat message: #{chat_msg}"
  if chat_msg[:msg_text] == "/say_hello"
    client.api_send_text_message chat_msg[:chat_type], chat_msg[:sender], "Hello! This was sent automagically"
    puts "Command executed!"
  end
end

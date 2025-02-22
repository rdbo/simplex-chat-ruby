require 'net/http'
require 'logger'
require_relative '../lib/simplex-chat'

client = SimpleXChat::ClientAgent.new URI('ws://localhost:5225'), log_level: Logger::DEBUG
version = client.api_version
profile = client.api_profile
address = client.api_get_user_address || client.api_create_user_address
contacts = client.api_contacts
groups = client.api_groups
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

# resp = client.api_send_text_message SimpleXChat::ChatType::GROUP, "new_group", "HELLO"
# puts "------------------------------------"
# puts "Send text message response: #{resp}"
# puts "------------------------------------"

puts "Listening for messages..."
loop do
  msg = client.next_message
  if msg == nil
    puts "Message queue is closed"
    break
  end
  puts "Received message"
end

# frozen_string_literal: true

require 'net/http'
require 'logger'
require_relative '../lib/simplex-chat'
include SimpleXChat

puts "Connecting client..."
client = ClientAgent.new URI('ws://localhost:5225'), log_level: Logger::DEBUG

puts "Sending commands..."
version = client.api_version
profile = client.api_profile
address = client.api_get_user_address || client.api_create_user_address
contacts = client.api_contacts
groups = client.api_groups
network = client.api_network socks: "on" # Enable Tor/SOCKS/Onion routing
# client.api_auto_accept true

puts "==================================="
puts
puts
puts "SimpleX Chat version: #{version}"
puts "Name: #{profile['name']}"
puts "Address: #{address}"
puts "SOCKS Mode: #{network["socksMode"]}"
puts "Preferences:"
profile["preferences"].each { |k, v| puts "  - #{k} => #{v && 'yes' || 'no'}"}
puts "Contacts:"
contacts.each { |c| puts "  - #{c['name']} (#{c['id']}) -> #{c['mergedPreferences'].map{|k, v| "#{k}: #{v}"}.join ', '}"}
puts "Groups:"
groups.each { |g| puts "  - #{g['name']} (#{g['id']}) -> alias: #{g['memberName']}, role: #{g['memberRole']}, members: #{g['currentMembers']}" }
puts
puts
puts "==================================="

### COMMANDS ###

def kick_command(client, group, issuer, issuer_role, subject)
  subject = subject.gsub(/^@/, "")
  unless [GroupMemberRole::OWNER, GroupMemberRole::ADMIN].include?(issuer_role)
    client.api_send_text_message ChatType::GROUP, group, "@#{issuer}: You do not have permissions to run this command"
    return
  end

  # TODO: Check member role before kicking him - he may be an admin or owner (?)
  #       Maybe simplex does this for us

  begin
    client.api_kick_group_member group, subject
    client.api_send_text_message ChatType::GROUP, group, "@#{issuer}: Kicked member '#{subject}' from '#{group}'"
  rescue => e
    client.api_send_text_message ChatType::GROUP, group, "@#{issuer}: Failed to kick group member '#{subject}'"
  end
end

### LISTENER ###

def event_listener(client)
  chat_msg = client.next_chat_message(max_backlog_secs: 5.0)
  if chat_msg == nil
    puts "Message queue is closed"
    return :stop
  end
  puts "Chat message: #{chat_msg}"

  msg_text = chat_msg[:msg_text]
  issuer = chat_msg[:contact]
  issuer_role = chat_msg[:contact_role]

  case msg_text
    when /\A!say_hello\z/
      client.api_send_text_message chat_msg[:chat_type], chat_msg[:sender], "@#{issuer}: Hello! This was sent automagically"
    when /\A!kick (\S*)\z/
      group = chat_msg[:group]
      subject = $1
      if group == nil
        client.api_send_text_message chat_msg[:chat_type], chat_msg[:sender], "Not in a group"
        return
      end

      kick_command client, group, issuer, issuer_role, subject
    when /\A!showcase\z/
      client.api_send_image chat_msg[:chat_type], chat_msg[:sender], "#{Dir.pwd}/showcase.png"
    when /\A!\S+.*/
      client.api_send_text_message chat_msg[:chat_type], chat_msg[:sender], "@#{issuer}: Unknown command"
    else
      return
  end
end

### MAIN LOOP ###

puts "Listening for messages..."
loop do
  begin
    break if event_listener(client) == :stop
  rescue SimpleXChat::GenericError => e
    puts "[!] Caught error: #{e}"
  rescue => e
    raise e
  end
end

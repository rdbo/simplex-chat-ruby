require 'net/http'
require 'logger'
require_relative '../lib/simplex-chat'

puts "Connecting client..."
client = SimpleXChat::ClientAgent.new URI('ws://localhost:5225'), log_level: Logger::DEBUG

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

### COMMANDS ###

def kick_command(client, group, member, contact, contact_role)
  member = member.gsub(/^@/, "")
  unless [SimpleXChat::GroupMemberRole::OWNER, SimpleXChat::GroupMemberRole::ADMIN].include?(contact_role)
    client.api_send_text_message SimpleXChat::ChatType::GROUP, group, "@#{contact}: You do not have permissions to run this command"
    return
  end

  # TODO: Check member role before kicking him - he may be an admin or owner (?)
  #       Maybe simplex does this for us

  begin
    client.api_kick_group_member group, member
    client.api_send_text_message SimpleXChat::ChatType::GROUP, group, "@#{contact}: Kicked member '#{member}' from '#{group}'"
  rescue => e
    client.api_send_text_message SimpleXChat::ChatType::GROUP, group, "@#{contact}: Failed to kick group member '#{member}'"
  end
end

#################

puts "Listening for messages..."
loop do
  chat_msg = client.next_chat_message
  if chat_msg == nil
    puts "Message queue is closed"
    break
  end
  puts "Chat message: #{chat_msg}"

  msg_text = chat_msg[:msg_text]
  contact = chat_msg[:contact]

  case msg_text
    when /\A!say_hello\z/
      client.api_send_text_message chat_msg[:chat_type], chat_msg[:sender], "@#{contact}: Hello! This was sent automagically"
    when /\A!kick (\S*)\z/
      group = chat_msg[:group]
      member = $1
      contact_role = chat_msg[:contact_role]
      if group == nil
        client.api_send_text_message chat_msg[:chat_type], chat_msg[:sender], "Not in a group"
        next
      end

      kick_command client, group, member, contact, contact_role
    when /\A!\S+.*/
      client.api_send_text_message chat_msg[:chat_type], chat_msg[:sender], "@#{contact}: Unknown command"
    else
      next
  end
end

# frozen_string_literal: true

require 'net/http'
require 'logger'
require_relative '../lib/simplex-chat'
require_relative 'cmd-runner'
require_relative 'commands'
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
last_messages = client.api_tail message_count: 5
last_chats = client.api_chats 5
# client.api_auto_accept true

command_prefix = '!'
commands = [SayHelloCommand.new, KickCommand.new, ShowcaseCommand.new]

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
puts "Last Messages:"
last_messages.each{ |m| puts "  - #{m[:chat_type]}#{m[:sender]}: #{m[:msg_text]}" }
puts "Last Chats:"
last_chats.each{ |c| puts "  - #{c[:chat_type]}#{c[:conversation]}" }
puts "Commands:"
commands.each { |cmd| puts "  - #{command_prefix}#{cmd.name}: #{cmd.desc}"}
puts
puts
puts "==================================="

runner = BasicCommandRunner.new(client, commands, command_prefix)
runner.listen

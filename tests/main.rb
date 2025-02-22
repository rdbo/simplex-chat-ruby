require 'net/http'
require_relative '../lib/simplex-chat'

puts 'Hello'


client = SimpleXChat::ClientAgent.new URI('ws://localhost:5225')
client.connect
client.listen

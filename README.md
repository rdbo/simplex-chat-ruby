# simplex-chat-ruby
A port for the SimpleX Chat client API for Ruby

## License
This project is licensed under the GNU AGPL-3.0 (no later versions).

Read `LICENSE` for more information.

## Showcase

![showcase](showcase.png)

## Usage

1. Install the Gem from RubyGems

        gem install simplex-chat

2. Start your local simplex-chat client on port 5225 (or any port you wish)

        simplex-chat -p 5225

3. Connect the `SimpleXChat::ClientAgent` to your local client

        require 'simplex-chat'
        require 'net/http'

        client = SimpleXChat::ClientAgent.new URI('ws://localhost:5225')

4. Now the client is connected and you can start using the APIs

        # Get version
        version = client.api_version
        puts "SimpleX Chat version: #{version}"

        # Send text message
        client.api_send_text_message SimpleXChat::ChatType::DIRECT, "some_user", "Hey, I'm using the Ruby API!"

        # Listen to incoming client messages
        loop do
            msg = client.next_message
            puts "New message from the client: #{msg}"
        end

        # Much more... Read the examples for more information

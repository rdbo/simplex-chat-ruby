module SimpleXChat
  class BasicCommand
    attr_reader :name, :num_args, :desc, :min_role

    # TODO: Allow optional arguments
    def initialize(name, desc="", num_args: 0, min_role: GroupMemberRole::MEMBER)
      @name = name
      @num_args = num_args
      @desc = desc
      @min_role = min_role
    end

    def execute(client, chat_msg, args)
      raise NoMethodError.new(
        "[!] Default BasicCommand::execute called, nothing will be done\n" \
        "    Extend this class to implement custom execution behavior"
      )
    end
  end

  class BasicCommandRunner
    # TODO: Consider using logger
    def initialize(client, commands, prefix)
      @client = client
      @commands = commands.map { |cmd|
        { "#{prefix}#{cmd.name}" => cmd }
      }.reduce({}, &:merge)
      @prefix = prefix
    end

    def listen(max_backlog_secs: 5.0)
      loop do
        begin
          break if process_next_event(max_backlog_secs) == :stop
        rescue SimpleXChat::GenericError => e
          puts "[!] Caught error: #{e}"
        rescue => e
          raise e
        end
      end
    end

    private

    def process_next_event(max_backlog_secs)
      chat_msg = @client.next_chat_message(max_backlog_secs: max_backlog_secs)
      if chat_msg == nil
        puts "Message queue is closed"
        return :stop
      end
      puts "Chat message: #{chat_msg}"

      msg_text = chat_msg[:msg_text]
      chat_type = chat_msg[:chat_type]
      issuer = chat_msg[:contact]
      issuer_role = chat_msg[:contact_role]
      sender = chat_msg[:sender]

      # Verify if this is a registered command
      message_items = msg_text.split(" ")
      first_word = message_items[0]

      # React to all messages we will process
      if first_word.start_with?(@prefix)
        @client.api_reaction chat_msg[:chat_type], chat_msg[:sender_id], chat_msg[:msg_item_id], emoji: '🚀'
      end

      command = @commands[first_word]
      if command == nil
        @client.api_send_text_message chat_msg[:chat_type], chat_msg[:sender], "@#{issuer}: Unknown command"
        return
      end

      # Verify that user has permissions to run the command
      role_hierarchy = {
        GroupMemberRole::MEMBER => 0,
        GroupMemberRole::ADMIN => 1,
        GroupMemberRole::OWNER => 2
      }
      perms = role_hierarchy[issuer_role]
      if perms == nil or perms < role_hierarchy[command.min_role]
        @client.api_send_text_message chat_msg[:chat_type], chat_msg[:sender], "@#{issuer}: You do not have permission to run this command (required: #{command.min_role})"
        return
      end

      # Verify arguments
      args = message_items[1..]
      if args.length != command.num_args
        @client.api_send_text_message chat_msg[:chat_type], chat_msg[:sender], "@#{issuer}: Incorrect number of arguments (required: #{command.num_args})"
        return
      end

      # Run command
      puts "Executing command: #{command} for: #{chat_type}#{sender} [#{issuer}]: #{msg_text}"
      command.execute @client, chat_msg, args
    end
  end
end

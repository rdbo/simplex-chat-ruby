module SimpleXChat
  class BasicCommand
    attr_reader :name, :num_args, :desc, :min_role

    # TODO: Allow optional arguments
    def initialize(name, desc="", num_args: 0, min_role: GroupMemberRole::MEMBER,
                   per_sender_cooldown_secs: nil, per_issuer_cooldown_secs: nil)
      @name = name
      @num_args = num_args
      @desc = desc
      @min_role = min_role
      @per_sender_cooldown_secs = per_sender_cooldown_secs
      @per_issuer_cooldown_secs = per_issuer_cooldown_secs
      @last_runs = {
        :per_sender => {},
        :per_issuer => {}
      }
      @last_runs_lock = Mutex.new
    end

    def validate_and_execute(client, chat_msg, args)
      return if not validate(client, chat_msg, args)
      begin
        execute client, chat_msg, args
      rescue
        client.api_send_text_message chat_msg[:chat_type], chat_msg[:sender], "@#{chat_msg[:contact]}: Failed to execute command"
      end
    end

    private

    def validate(client, chat_msg, args)
      msg_text = chat_msg[:msg_text]
      chat_type = chat_msg[:chat_type]
      issuer = chat_msg[:contact]
      issuer_role = chat_msg[:contact_role]
      sender = chat_msg[:sender]

      # Verify that user has permissions to run the command
      role_hierarchy = {
        GroupMemberRole::MEMBER => 0,
        GroupMemberRole::ADMIN => 1,
        GroupMemberRole::OWNER => 2
      }
      perms = role_hierarchy[issuer_role]
      if issuer_role != nil and perms == nil || perms < role_hierarchy[@min_role]
        client.api_send_text_message chat_type, sender, "@#{issuer}: You do not have permission to run this command (required: #{@min_role})"
        return false
      end

      # Verify arguments
      if args.length != @num_args
        client.api_send_text_message chat_type, sender, "@#{issuer}: Incorrect number of arguments (required: #{@num_args})"
        return false
      end

      # Verify per sender cooldown
      # NOTE: This should be the last verification, because
      #       it will update the last-validated-runs object
      is_on_cooldown = true
      remaining_cooldown = 0.0
      chat = "#{chat_type}#{sender}"
      chat_and_issuer = "#{chat_type}#{sender}[#{issuer}]"
      @last_runs_lock.synchronize {
        sender_last_run = @last_runs[:per_sender][chat]
        issuer_last_run = @last_runs[:per_issuer][chat_and_issuer]
        now = Time.now
        if sender_last_run != nil && @per_sender_cooldown_secs != nil
          time_diff = now - sender_last_run
          if time_diff < @per_sender_cooldown_secs
            remaining_cooldown = @per_sender_cooldown_secs - time_diff
          end
        end

        if issuer_last_run != nil && @per_issuer_cooldown_secs != nil
          time_diff = now - issuer_last_run
          if time_diff < @per_issuer_cooldown_secs
            cooldown = @per_issuer_cooldown_secs - time_diff
            remaining_cooldown = [cooldown, remaining_cooldown].max
          end
        end

        break if remaining_cooldown > 0.0

        @last_runs[:per_sender][chat] = now
        @last_runs[:per_issuer][chat_and_issuer] = now
        is_on_cooldown = false
      }

      if is_on_cooldown
        client.api_send_text_message chat_type, sender, "@#{issuer}: On cooldown, try again in #{remaining_cooldown.round(1)} seconds"
        return false
      end
      

      return true
    end

    def execute(client, chat_msg, args)
      raise NoMethodError.new(
        "[!] Default BasicCommand::execute called, nothing will be done\n" \
        "    Extend this class to implement custom execution behavior"
      )
    end
  end

  class BasicCommandRunner
    def initialize(client, commands, prefix)
      @client = client
      @commands = commands.map { |cmd|
        { "#{prefix}#{cmd.name}" => cmd }
      }.reduce({}, &:merge)
      @prefix = prefix
      @logger = Logging.logger
    end

    def listen(max_backlog_secs: 5.0)
      loop do
        begin
          break if process_next_event(max_backlog_secs) == :stop
        rescue SimpleXChat::GenericError => e
          @logger.error("[!] Caught error: #{e}")
        rescue => e
          raise e
        end
      end
    end

    private

    def process_next_event(max_backlog_secs)
      chat_msg = @client.next_chat_message(max_backlog_secs: max_backlog_secs)
      if chat_msg == nil
        @logger.warn("Message queue is closed")
        return :stop
      end
      @logger.debug("Chat message: #{chat_msg}")

      msg_text = chat_msg[:msg_text]
      chat_type = chat_msg[:chat_type]
      issuer = chat_msg[:contact]
      issuer_role = chat_msg[:contact_role]
      sender = chat_msg[:sender]

      # Skip automated group messages and empty messages
      return if issuer == nil or msg_text.length == 0

      # Verify if message is a command
      message_items = msg_text.split(" ")
      first_word = message_items[0]
      return if not first_word.start_with?(@prefix)

      # React to all messages we will process
      @client.api_reaction chat_msg[:chat_type], chat_msg[:sender_id], chat_msg[:msg_item_id], emoji: '🚀'

      # Verify if this is a registered command
      command = @commands[first_word]
      if command == nil
        @client.api_send_text_message chat_msg[:chat_type], chat_msg[:sender], "@#{issuer}: Unknown command"
        return
      end

      args = message_items[1..]

      # Run command
      @logger.debug("Validating and executing command '#{command.name}' for: #{chat_type}#{sender} [#{issuer}]: #{msg_text}")
      command.validate_and_execute @client, chat_msg, args
    end
  end
end

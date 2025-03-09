class SayHelloCommand < BasicCommand
  def initialize()
    super("say_hello", "Greet the command issuer", num_args: 0)
  end

  def execute(client, chat_msg, args)
    issuer = chat_msg[:contact]
    client.api_send_text_message chat_msg[:chat_type], chat_msg[:sender], "@#{issuer}: Hello! This was sent automagically"
  end
end

class KickCommand < BasicCommand
  def initialize()
    super("kick", "Remove a member from the group", num_args: 1, min_role: GroupMemberRole::ADMIN)
  end

  def execute(client, chat_msg, args)
    subject = args[0].gsub(/^@/, "")
    issuer = chat_msg[:contact]
    group = chat_msg[:group]
    if group == nil
      client.api_send_text_message chat_msg[:chat_type], chat_msg[:sender], "Not in a group"
      return
    end

    begin
      client.api_kick_group_member group, subject
      client.api_send_text_message ChatType::GROUP, group, "@#{issuer}: Kicked member '#{subject}' from '#{group}'"
    rescue
      client.api_send_text_message ChatType::GROUP, group, "@#{issuer}: Failed to kick group member '#{subject}'"
    end
  end
end

class ShowcaseCommand < BasicCommand
  def initialize(cooldown_secs=30.0)
    @sender_lock = Mutex.new
    @sender_cooldown = {}
    @cooldown_secs = cooldown_secs

    super("showcase", "Send a showcase image of the SimpleX Chat Ruby API", num_args: 0)
  end

  def execute(client, chat_msg, args)
    sender = chat_msg[:sender]
    issuer = chat_msg[:contact]
    chat_type = chat_msg[:chat_type]
    chat = "#{chat_type}#{sender}"

    cooldown_period_over = false
    remaining_cooldown = 0.0
    @sender_lock.synchronize {
      last_run = @sender_cooldown[chat]
      now = Time.now
      if last_run != nil
        time_diff = now - last_run
        if time_diff < @cooldown_secs
          remaining_cooldown = @cooldown_secs - time_diff
          break
        end
      end

      @sender_cooldown[chat] = now
      cooldown_period_over = true
    }

    if not cooldown_period_over
      client.api_send_text_message chat_type, sender, "@#{issuer}: On cooldown, try again in #{remaining_cooldown.round(1)} seconds"
      return
    end

    # client.api_send_image chat_msg[:chat_type], chat_msg[:sender], "#{Dir.pwd}/showcase.png"
    client.api_send_text_message chat_type, sender, "@#{issuer}: NOT ON COOLDOWN"
  end
end

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
    super("showcase", "Send a showcase image of the SimpleX Chat Ruby API", num_args: 0, per_sender_cooldown_secs: 30.0)
  end

  def execute(client, chat_msg, args)
    client.api_send_image chat_msg[:chat_type], chat_msg[:sender], "#{Dir.pwd}/showcase.png"
  end
end

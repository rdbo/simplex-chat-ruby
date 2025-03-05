# frozen_string_literal: true

require_relative 'simplex-chat/version'
require_relative 'simplex-chat/errors'
require_relative 'simplex-chat/patches'
require_relative 'simplex-chat/types'

module SimpleXChat
  require 'net/http'
  require 'logger'
  require 'json'
  require 'websocket'
  require 'concurrent'
  require 'time'

  class ClientAgent
    attr_accessor :on_message

    def initialize(client_uri, connect: true, log_level: Logger::INFO, timeout_ms: 10_000, interval_ms: 100)
      @uri = client_uri
      @message_queue = Queue.new
      @chat_message_queue = Queue.new
      @socket = nil
      @handshake = nil

      # Helpers for handling requests to and messages from the SXC client
      @listener_thread = nil
      @corr_id = Concurrent::AtomicFixnum.new(1) # Correlation ID for mapping client responses to command waiters
      @command_waiters = Concurrent::Hash.new
      @timeout_ms = timeout_ms
      @interval_ms = interval_ms

      @logger = Logger.new($stderr)
      @logger.level = log_level
      @logger.progname = 'simplex-chat'
      @logger.formatter = -> (severity, datetime, progname, msg) {
        "| [#{severity}] | #{datetime} | (#{progname}) :: #{msg}\n"
      }

      self.connect if connect

      @logger.debug("Initialized ClientAgent")
    end

    def connect
      @logger.debug("Connecting to: '#{@uri}'...")
      @socket = TCPSocket.new @uri.host, @uri.port
      @handshake = WebSocket::Handshake::Client.new(url: @uri.to_s)

      # Do websocket handshake
      @logger.debug("Doing handshake with: '#{@uri}'...")
      @socket.write @handshake.to_s
      resp = HTTPResponse.read_new(Net::BufferedIO.new(@socket))

      @listener_thread = Thread.new do
        frame = WebSocket::Frame::Incoming::Client.new(version: @handshake.version)
        loop do
          begin
            buf = @socket.read_nonblock 4096
            frame << buf
            obj = frame.next
            next if obj == nil
            @logger.debug("New message (raw): #{obj}")

            msg = JSON.parse obj.to_s
            # @logger.debug("New message: #{msg}")
            # @logger.debug("Command waiters: #{@command_waiters}")

            corr_id = msg["corrId"]
            resp = msg["resp"]
            single_use_queue = @command_waiters[corr_id]
            if corr_id != nil && single_use_queue != nil
              single_use_queue = @command_waiters[corr_id]
              single_use_queue.push(resp)
              @logger.debug("Message sent to waiter with corrId '#{corr_id}'")
            else
              @message_queue.push resp
              @logger.debug("Message put on message queue (number of messages in queue: #{@message_queue.size})")
            end
          rescue IO::WaitReadable
            IO.select([@socket])
            retry
          rescue IO::WaitWritable
            IO.select(nil, [@socket])
            retry
          rescue => e
            # TODO: Verify if this way of stopping the execution
            #       is graceful enough after implementing reconnects
            @logger.error "Unhandled exception caught: #{e}"
            @message_queue.close
            raise e
          end
        end
      end

      @logger.info("Successfully connected ClientAgent to: #{@uri}")
    end

    def next_message
      msg = @message_queue.pop
      @logger.debug("Message retrieved from queue (number of messages in queue: #{@message_queue.size})")
      msg
    end

    def next_chat_message(
      max_backlog_secs: 15.0 # if nil, it will process any incoming messages, including old ones
    )
      # NOTE: There can be more than one message per
      #       client message. Because of that, we use
      #       a chat message queue to insert one or
      #       more messages at a time, but poll just
      #       one at a time
      return @chat_message_queue.pop if not @chat_message_queue.empty?
  
      loop do
        msg = next_message
        break if msg == nil
        next if not ["chatItemUpdated", "newChatItems"].include?(msg["type"])

        # Handle one or more chat messages in a single client message
        new_chat_messages = nil
        if msg["type"] == "chatItemUpdated"
          new_chat_messages = [msg["chatItem"]]
        else
          new_chat_messages = msg["chatItems"]
        end

        new_chat_messages.each do |chat_item|
          chat_message = parse_chat_item chat_item

          time_diff = Time.now - chat_message[:msg_timestamp]
          if max_backlog_secs != nil && time_diff > max_backlog_secs
            @logger.debug("Skipped message (time diff: #{time_diff}, max allowed: #{max_backlog_secs}): #{chat_message}")
            next
          end

          @chat_message_queue.push chat_message
        end

        # NOTE: Even after parsing the messages, the
        #       chat message queue can be empty because
        #       all the messages are too old, so we have
        #       to check again
        return @chat_message_queue.pop if not @chat_message_queue.empty?
      end

      nil
    end

    def disconnect
      @listener_thread.terminate
      @socket.close
      @message_queue.clear
      @chat_message_queue.clear
    end

    # Sends a raw command to the SimpleX Chat client
    def send_command(cmd, timeout_ms: @timeout_ms, interval_ms: @interval_ms)
      corr_id = next_corr_id
      obj = {
        "corrId" => corr_id,
        "cmd" => cmd
      }
      json = obj.to_json
      frame = WebSocket::Frame::Outgoing::Client.new(version: @handshake.version, data: json, type: :text)

      # The listener thread will send the message
      # that matches the corrId to this single
      # use queue instead of the global message queue,
      # and this function will poll it to wait for the
      # command response
      single_use_queue = SizedQueue.new 1
      @command_waiters[corr_id] = single_use_queue
      @logger.debug("Created command waiter for command ##{corr_id}")

      @logger.debug("Sending command ##{corr_id}: #{json.to_s}")
      @socket.write frame.to_s

      @logger.debug("Waiting response for command ##{corr_id}...")
      msg = nil
      iterations = timeout_ms / interval_ms
      iterations.times do
        begin
          msg = single_use_queue.pop(true)
          break
        rescue ThreadError
          sleep(interval_ms / 1000.0)
        end
      end

      if msg == nil
        raise SendCommandError.new(json.to_s)
      end

      @logger.debug("Command ##{corr_id} finished successfully with response: #{msg}")

      msg
    ensure
      @command_waiters.delete corr_id
      @logger.debug("Cleaned up command waiter ##{corr_id}")
    end

    def api_version
      resp = send_command '/version'
      check_response_type(resp, "versionInfo")

      resp["versionInfo"]["version"]
    end

    def api_profile
      resp = send_command '/profile'
      check_response_type(resp, "userProfile")

      {
        "name" => resp["user"]["profile"]["displayName"],
        "preferences" => resp["user"]["fullPreferences"].map{|k, v| { k => v["allow"] == "yes"}}.reduce({}, :merge)
      }
    end

    def api_get_user_address
      resp = send_command "/show_address"
      resp_type = resp["type"]

      # Check if user doesn't have an address      
      if resp_type == "chatCmdError" && resp.dig("chatError", "storeError", "type") == "userContactLinkNotFound"
        return nil
      end
      check_response_type(resp, "userContactLink")

      resp["contactLink"]["connReqContact"]
    end

    def api_create_user_address
      resp = send_command '/address'
      check_response_type(resp, "userContactLinkCreated")

      resp["connReqContact"]
    end

    def api_send_text_message(chat_type, receiver, message)
      resp = send_command "#{chat_type}#{receiver} #{message}"
      check_response_type(resp, "newChatItems")

      resp["chatItems"]
    end

    def api_send_image(chat_type, receiver, file_path)
      resp = send_command "/image #{chat_type}#{receiver} #{file_path}"
      check_response_type(resp, "newChatItems")

      resp["chatItems"]
    end

    def api_send_file(chat_type, receiver, file_path)
      resp = send_command "/file #{chat_type}#{receiver} #{file_path}"
      check_response_type(resp, "newChatItems")

      resp["chatItems"]
    end

    def api_contacts
      resp = send_command "/contacts"
      check_response_type(resp, "contactsList")

      contacts = resp["contacts"]
      contacts.map{ |c| {
        "id" => c["contactId"],
        "name" => c["localDisplayName"],
        "preferences" => c["profile"]["preferences"].map{|k, v| { k => v["allow"] == "yes"}}.reduce({}, :merge),
        "mergedPreferences" => c["mergedPreferences"].map{|k, v| {
          k => (v["enabled"]["forUser"] && v["enabled"]["forContact"])
        }}.reduce({}, :merge),
      }}
    end

    def api_groups
      resp = send_command "/groups"
      check_response_type(resp, "groupsList")

      groups = resp["groups"]
      groups.map{ |entry| 
        group = entry[0]
        members = entry[1]

        {
          "id" => group["groupId"],
          "name" => group["localDisplayName"],
          "preferences" => group["fullGroupPreferences"].map{|k, v| { k => v["enable"] == "on" }}.reduce({}, :merge),
          "currentMembers" => members["currentMembers"],
          "invitedByContactId" => group.dig("membership", "invitedBy", "byContactId"),
          "invitedByGroupMemberId" => group.dig("membership", "invitedByGroupMemberId"),
          "memberName" => group["membership"]["localDisplayName"],
          "memberRole" => group["membership"]["memberRole"],
          "memberCategory" => group["membership"]["memberCategory"],
          "memberStatus" => group["membership"]["memberStatus"]
        }
      }
    end

    def api_auto_accept is_enabled
      onoff = is_enabled && "on" || "off"

      resp = send_command "/auto_accept #{onoff}"
      check_response_type(resp, "userContactLinkUpdated")

      nil
    end

    def api_kick_group_member(group, member)
      resp = send_command "/remove #{group} #{member}"
      check_response_type(resp, "userDeletedMember")
    end

    # Parameters for /network:
    #   - socks: on/off/<[ipv4]:port>
    #   - socks-mode: always/onion
    #   - smp-proxy: always/unknown/unprotected/never
    #   - smp-proxy-fallback: no/protected/yes
    #   - timeout: <seconds>
    def api_network(socks: nil, socks_mode: nil, smp_proxy: nil, smp_proxy_fallback: nil, timeout_secs: nil)
      args = {
        "socks" => socks,
        "socks-mode" => socks_mode,
        "smp-proxy" => smp_proxy,
        "smp-proxy-fallback" => smp_proxy_fallback,
        "timeout" => timeout_secs
      }
      command = '/network'
      args.each do |param, value|
        next if value == nil
        command += " #{param}=#{value}"
      end
      resp = send_command command
      check_response_type(resp, "networkConfig")

      resp["networkConfig"]
    end

    def api_tail(chat_type: nil, conversation: nil, message_count: nil)
      cmd = "/tail"
      cmd += " #{chat_type}#{conversation}" if chat_type != nil && conversation != nil
      cmd += " #{message_count}" if message_count != nil
      resp = send_command cmd
      check_response_type(resp, "chatItems")

      resp["chatItems"].map{|chat_item| parse_chat_item chat_item}
    end

    def api_chats(
      chat_count=20 # if nil, will return all the chats
    )
      param = chat_count != nil ? "#{chat_count}" : "all"
      cmd = "/chats #{param}"
      resp = send_command cmd
      check_response_type(resp, "chats")

      resp["chats"].map do |chat|
        chat_type = parse_chat_info_type chat["chatInfo"]["type"]
        next if chat_type == nil # WARN: Chat type "local" is currently ignored
        conversation = nil
        if chat_type == ChatType::GROUP
          conversation = chat["chatInfo"]["groupInfo"]["localDisplayName"]
        else
          conversation = chat["chatInfo"]["contact"]["localDisplayName"]
        end

        {
          :chat_type => chat_type,
          :conversation => conversation
        }
      end.filter { |x| x != nil }
    end

    # TODO: Add `/_reaction members` support, either on this
    #       function or in a separate one
    def api_reaction(chat_type, chat_id, message_item_id, add: true, emoji: '👍')
      onoff = add ? "on" : "off"
      param_obj = {
        "type" => "emoji",
        "emoji" => emoji
      }
      cmd = "/_reaction #{chat_type}#{chat_id} #{message_item_id} #{onoff} #{param_obj.to_json}"
      resp = send_command cmd
      check_response_type(resp, "chatItemReaction")
    end

    private

    def check_response_type(resp, expected_resp_type)
      resp_type = resp["type"]
      raise UnexpectedResponseError.new(resp_type, expected_resp_type) unless resp_type == expected_resp_type
    end

    def next_corr_id
      # The correlation ID has to be a string
      (@corr_id.update { |x| x + 1 } - 1).to_s(10)
    end

    def parse_chat_info_type(type)
      chat_info_types = {
        "direct" => ChatType::DIRECT,
        "group" => ChatType::GROUP
      }

      chat_info_types.dig(type)
    end

    def parse_chat_item(chat_item)
      chat_type = parse_chat_info_type chat_item["chatInfo"]["type"]
      group = nil
      group_id = nil
      sender = nil
      sender_id = nil
      contact = nil
      contact_id = nil
      contact_role = nil
      if chat_type == ChatType::GROUP
        # NOTE: The group can "send messages" without a contact
        #       For example, when a member is removed, the group
        #       sends a message about his removal, with no contact
        contact = chat_item.dig "chatItem", "chatDir", "groupMember", "localDisplayName"
        contact_id = chat_item.dig "chatItem", "chatDir", "groupMember", "groupMemberId"
        contact_role = chat_item.dig "chatItem", "chatDir", "groupMember", "memberRole"
        group = chat_item["chatInfo"]["groupInfo"]["localDisplayName"]
        group_id = chat_item["chatInfo"]["groupInfo"]["groupId"]
        sender = group
        sender_id = group_id
      else
        contact = chat_item["chatInfo"]["contact"]["localDisplayName"]
        contact_id = chat_item["chatInfo"]["contact"]["contactId"]
        sender = contact
        sender_id = contact_id
      end

      msg_text = chat_item["chatItem"]["meta"]["itemText"]
      msg_item_id = chat_item["chatItem"]["meta"]["itemId"]
      timestamp = Time.parse(chat_item["chatItem"]["meta"]["updatedAt"])
      msg_image_preview = chat_item.dig "chatItem", "content", "msgContent", "image"

      chat_message = {
        :chat_type => chat_type,

        :sender => sender,
        :sender_id => sender_id,

        :contact => contact,
        :contact_id => contact_id,
        :contact_role => contact_role,

        :group => group,
        :group_id => group_id,

        :msg_text => msg_text,
        :msg_item_id => msg_item_id,
        :msg_timestamp => timestamp,
        :msg_img_preview => msg_image_preview
      }
    end
  end
end

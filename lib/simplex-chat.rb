# frozen_string_literal: true

require_relative 'simplex-chat/version'

module SimpleXChat
  require 'net/http'
  require 'logger'
  require 'json'
  require 'websocket'
  require 'concurrent'

  # Fixes regex match for status line in HTTPResponse
  class HTTPResponse < Net::HTTPResponse
    class << self
      def read_status_line(sock)
        str = sock.readline
        m = /\AHTTP(?:\/(\d+\.\d+))?\s+(\d\d\d)(?:\s+(.*))?\Z/in.match(str) or
          raise Net::HTTPBadResponse, "wrong status line: #{str.dump}"
        m.captures
      end
    end
  end

  module ChatType
    DIRECT = '@'
    GROUP = '#'
    CONTACT_REQUEST = '<@'
  end

  class ClientAgent
    attr_accessor :on_message

    def initialize client_uri, connect: true, log_level: Logger::INFO
      @uri = client_uri
      @message_queue = SizedQueue.new 4096
      @socket = nil
      @handshake = nil

      # Helpers for handling requests to and messages from the SXC client
      @listener_thread = nil
      @corr_id = Concurrent::AtomicFixnum.new(1) # Correlation ID for mapping client responses to command waiters
      @command_waiters = Concurrent::Hash.new

      @logger = Logger.new($stderr)
      @logger.level = log_level
      @logger.progname = 'simplex-chat'
      @logger.formatter = -> (severity, datetime, progname, msg) {
        "| [#{severity}] | #{datetime} | (#{progname}) :: #{msg}\n"
      }

      if connect
        self.connect
      end

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

            corr_id = msg["corrId"]
            resp = msg["resp"]
            single_use_queue = @command_waiters[corr_id]
            if corr_id != nil && single_use_queue != nil
              single_use_queue = @command_waiters[corr_id]
              single_use_queue.push(resp)
              @logger.debug("Message sent to waiter with corrId '#{corr_id}'")
            else
              @message_queue.push resp
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
            puts "Unhandled exception caught: #{e}"
            @message_queue.close
            raise e
          end
        end
      end

      @logger.info("Successfully connected ClientAgent to: #{@uri}")
    end

    def next_message
      @message_queue.pop
    end

    def disconnect
      @listener_thread.terminate
      @socket.close
      @message_queue.clear
    end

    # Sends a raw command to the SimpleX Chat client
    def send_command(cmd)
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

      @socket.write frame.to_s

      msg = nil
      100.times do
        begin
          msg = single_use_queue.pop(true)
          break
        rescue ThreadError
          sleep 0.1
        end
      end

      if msg == nil
        raise "Failed to send command"
      end

      msg
    end

    def api_version
      resp = send_command '/version'
      resp_type = resp["type"]
      raise "Unexpected response: #{resp_type}" if resp_type != "versionInfo"

      resp["versionInfo"]["version"]
    end

    def api_profile
      resp = send_command '/profile'
      resp_type = resp["type"]
      raise "Unexpected response: #{resp_type}" if resp_type != "userProfile"

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
  
      raise "Unexpected response: #{resp_type}" if resp_type != "userContactLink"

      resp["contactLink"]["connReqContact"]
    end

    def api_create_user_address
      resp = send_command '/address'
      resp_type = resp["type"]
      raise "Unexpected response: #{resp_type}" if resp_type != "userContactLinkCreated"

      resp["connReqContact"]
    end

    def api_send_text_message(chat_type, contact, message)
      resp = send_command "#{chat_type}#{contact} #{message}"
      resp_type = resp["type"]
      raise "Unexpected response: #{resp_type}" if resp_type != "newChatItems"

      resp["chatItems"]
    end

    def api_contacts
      resp = send_command "/contacts"
      resp_type = resp["type"]
      raise "Unexpected response: #{resp_type}" if resp_type != "contactsList"

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
      resp_type = resp["type"]
      raise "Unexpected response: #{resp_type}" if resp_type != "groupsList"

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

    private

    def next_corr_id
      # The correlation ID has to be a string
      (@corr_id.update { |x| x + 1 } - 1).to_s(10)
    end
  end
end

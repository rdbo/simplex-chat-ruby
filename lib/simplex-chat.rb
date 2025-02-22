module SimpleXChat
  require 'websocket'
  require 'logger'
  require 'net/http'

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

  class ClientAgent
    attr_accessor :on_message

    def initialize client_uri, connect: false, log_level: Logger::INFO
      @uri = client_uri
      @message_queue = SizedQueue.new 4096
      @socket = nil
      @listener_thread = nil
      @handshake = nil
      @corr_id = 1 # Correlation ID for mapping client responses to command waiters
      @logger = Logger.new($stderr)
      @logger.progname = 'simplex-chat'
      @logger.formatter = -> (severity, datetime, progname, msg) {
        "[#{severity}] | #{datetime} | (#{progname}) :: #{msg}\n"
      }

      if connect
        self.connect
      end

      @logger.debug("Initialized ClientAgent")
    end

    def connect
      @logger.debug("Connecting to: '#{@uri}'...")
      @socket = Net::BufferedIO.new(TCPSocket.new @uri.host, @uri.port)
      @handshake = WebSocket::Handshake::Client.new(url: @uri.to_s)

      # Do websocket handshake
      @logger.debug("Doing handshake with: '#{@uri}'...")
      @socket.write @handshake.to_s
      resp = HTTPResponse.read_new @socket

      @listener_thread = Thread.new do
        
      end

      @logger.info("Successfully connected ClientAgent to: #{@uri}")
    end

    def disconnect
      @listener_thread.terminate
      @socket.close
      @message_queue.clear
    end

    def connected?
      @socket != nil
    end
  end
end

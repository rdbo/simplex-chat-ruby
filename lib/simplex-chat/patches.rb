# frozen_string_literal: true

module SimpleXChat
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
end

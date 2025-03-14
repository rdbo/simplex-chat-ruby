require 'logger'

module SimpleXChat
  module Logging
    @@logger = nil

    def self.logger(dest: $stderr, log_level: Logger::INFO)
      if @@logger == nil
        @@logger = Logger.new(dest)
        @@logger.level = log_level
        @@logger.progname = 'simplex-chat'
        @@logger.formatter = -> (severity, datetime, progname, msg) {
          "| [#{severity}] | #{datetime} | (#{progname}) :: #{msg}\n"
        }
      end

      @@logger
    end
  end
end

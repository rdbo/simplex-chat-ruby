# frozen_string_literal: true

module SimpleXChat
  # All SimpleX-related errors will inherit from GenericError
  # These errors should be recoverable
  class GenericError < StandardError
  end

  class SendCommandError < GenericError
    def initialize(cmd)
      super "Failed to send command: #{cmd}"
    end
  end

  class UnexpectedResponseError < GenericError
    def initialize(type, expected_type)
      super "Unexpected response type: #{type} (expected: #{expected_type})"
    end
  end
end

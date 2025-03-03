# frozen_string_literal: true

module SimpleXChat
  module ChatType
    DIRECT = '@'
    GROUP = '#'
    CONTACT_REQUEST = '<@'
  end

  module GroupMemberRole
    AUTHOR = 'author' # reserved and unused as of now, but added anyways
    OWNER = 'owner'
    ADMIN = 'admin'
    MEMBER = 'member'
    OBSERVER = 'observer'
  end
end

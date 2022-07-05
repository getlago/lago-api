# frozen_string_literal: true

module CurrentContext
  thread_mattr_accessor :organization_id
  thread_mattr_accessor :membership_id
end

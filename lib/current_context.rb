# frozen_string_literal: true

module CurrentContext
  thread_mattr_accessor :organization_id
  thread_mattr_accessor :membership_id

  def self.organization_id=(organization_id)
    self.organization_id = organization_id
  end

  def self.membership_id=(membership_id)
    self.membership_id = membership_id
  end
end

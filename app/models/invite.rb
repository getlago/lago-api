# frozen_string_literal: true

class Invite < ApplicationRecord
  belongs_to :organization
  belongs_to :recipient, class_name: 'Membership', foreign_key: :membership_id, optional: true

  INVITE_STATUS = %i[
    pending
    accepted
    revoked
  ].freeze

  enum status: INVITE_STATUS

  validates :email, email: true
  validates :token, uniqueness: true

  def mark_as_revoked!(timestamp = Time.current)
    self.revoked_at ||= timestamp
    revoked!
  end
end

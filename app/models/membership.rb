# frozen_string_literal: true

class Membership < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :organization
  belongs_to :user

  STATUSES = [
    :active,
    :revoked,
  ].freeze

  ROLES = { admin: 0 }.freeze

  enum status: STATUSES
  enum role: ROLES

  validates :user_id, uniqueness: { conditions: -> { where(revoked_at: nil) }, scope: :organization_id }

  def mark_as_revoked!(timestamp = Time.current)
    self.revoked_at ||= timestamp
    revoked!
  end
end

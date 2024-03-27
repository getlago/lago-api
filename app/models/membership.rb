# frozen_string_literal: true

class Membership < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :organization
  belongs_to :user

  STATUSES = [
    :active,
    :revoked
  ].freeze

  enum status: STATUSES
  enum role: {admin: 0}

  validates :user_id, uniqueness: {conditions: -> { where(revoked_at: nil) }, scope: :organization_id}

  def mark_as_revoked!(timestamp = Time.current)
    self.revoked_at ||= timestamp
    revoked!
  end
end

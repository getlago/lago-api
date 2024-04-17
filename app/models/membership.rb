# frozen_string_literal: true

class Membership < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :organization
  belongs_to :user

  STATUSES = [
    :active,
    :revoked,
  ].freeze

  ROLES = {
    admin: 0,
    manager: 1,
    finance: 2,
  }.freeze

  enum status: STATUSES
  enum role: ROLES

  validates :user_id, uniqueness: { conditions: -> { where(revoked_at: nil) }, scope: :organization_id }

  def mark_as_revoked!(timestamp = Time.current)
    self.revoked_at ||= timestamp
    revoked!
  end

  def can?(permission)
    permissions_hash[permission.to_s]
  end

  def permissions_hash
    case role
    when 'admin'
      Permission::ADMIN_PERMISSIONS_HASH
    when 'manager'
      Permission::MANAGER_PERMISSIONS_HASH
    when 'finance'
      Permission::FINANCE_PERMISSIONS_HASH
    else
      {}
    end
  end
end

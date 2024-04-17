# frozen_string_literal: true

class Membership < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :organization
  belongs_to :user
  has_many :permissions

  STATUSES = [
    :active,
    :revoked,
  ].freeze

  ROLES = [
    :admin,
    :manager,
    :finance,
  ].freeze

  enum status: STATUSES
  enum role: ROLES

  validates :user_id, uniqueness: { conditions: -> { where(revoked_at: nil) }, scope: :organization_id }

  def mark_as_revoked!(timestamp = Time.current)
    self.revoked_at ||= timestamp
    revoked!
  end

  def admin?
    role == 'admin'
  end

  def can?(permission)
    permissions_hash[permission.to_s]
  end

  def permissions_hash
    return Permission::ADMIN_PERMISSIONS_HASH if admin?

    @permissions_hash ||= Permission::DEFAULT_PERMISSIONS_HASH.merge(permissions.pluck(:name, :value).to_h)
  end
end

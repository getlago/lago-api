# frozen_string_literal: true

class Membership < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :organization
  belongs_to :user

  has_many :data_exports

  STATUSES = [
    :active,
    :revoked
  ].freeze

  ROLES = {
    admin: 0,
    manager: 1,
    finance: 2
  }.freeze

  enum :status, STATUSES
  enum :role, ROLES

  validates :user_id, uniqueness: {conditions: -> { where(revoked_at: nil) }, scope: :organization_id}

  def mark_as_revoked!(timestamp = Time.current)
    self.revoked_at ||= timestamp
    revoked!
  end

  def can?(permission)
    permissions_hash[permission.to_s]
  end

  def permissions_hash
    case role
    when "admin"
      Permission::ADMIN_PERMISSIONS_HASH
    when "manager"
      Permission::MANAGER_PERMISSIONS_HASH
    when "finance"
      Permission::FINANCE_PERMISSIONS_HASH
    else
      {}
    end
  end
end

# == Schema Information
#
# Table name: memberships
#
#  id              :uuid             not null, primary key
#  revoked_at      :datetime
#  role            :integer          default("admin"), not null
#  status          :integer          default("active"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#  user_id         :uuid             not null
#
# Indexes
#
#  index_memberships_on_organization_id              (organization_id)
#  index_memberships_on_user_id                      (user_id)
#  index_memberships_on_user_id_and_organization_id  (user_id,organization_id) UNIQUE WHERE (revoked_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (user_id => users.id)
#

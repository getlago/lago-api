# frozen_string_literal: true

class MembershipRole < ApplicationRecord
  include Discard::Model

  self.discard_column = :deleted_at
  default_scope -> { kept }

  belongs_to :organization
  belongs_to :membership
  belongs_to :role

  scope :admins, -> { joins(:role).where(roles: {admin: true}) }

  # Only communicate errors on last role discard
  before_discard :forbid_last_admin_role_discard
  before_discard :forbid_last_membership_role_discard

  private

  def forbid_last_admin_role_discard
    return unless role.admin?
    return if organization.membership_roles.admins.where.not(id:).exists?

    errors.add(:base, :last_admin_role)
    throw(:abort)
  end

  def forbid_last_membership_role_discard
    return if membership.membership_roles.where.not(id:).exists?

    errors.add(:base, :last_membership_role)
    throw(:abort)
  end
end

# == Schema Information
#
# Table name: membership_roles
# Database name: primary
#
#  id              :uuid             not null, primary key
#  deleted_at      :datetime
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  membership_id   :uuid             not null
#  organization_id :uuid             not null
#  role_id         :uuid             not null
#
# Indexes
#
#  index_membership_roles_by_membership_and_organization  (membership_id,organization_id) WHERE (deleted_at IS NULL)
#  index_membership_roles_on_role_id                      (role_id)
#  index_membership_roles_uniqueness                      (membership_id,role_id) UNIQUE WHERE (deleted_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...                   (role_id => roles.id)
#  membership_role_membership_fk  ([membership_id, organization_id] => memberships[id, organization_id])
#

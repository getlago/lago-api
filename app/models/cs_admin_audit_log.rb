# frozen_string_literal: true

class CsAdminAuditLog < ApplicationRecord
  belongs_to :actor_user, class_name: "User"
  belongs_to :organization
  belongs_to :rollback_of, class_name: "CsAdminAuditLog", optional: true

  ACTIONS = {toggle_on: 0, toggle_off: 1, org_created: 2, rollback: 3}.freeze
  FEATURE_TYPES = {premium_integration: 0, feature_flag: 1}.freeze

  enum :action, ACTIONS, validate: true
  enum :feature_type, FEATURE_TYPES, validate: true

  validates :actor_email, presence: true
  validates :action, presence: true
  validates :feature_type, presence: true
  validates :feature_key, presence: true
  validates :reason, presence: true, length: {minimum: 10, maximum: 500}

  scope :newest_first, -> { order(created_at: :desc) }
end

# == Schema Information
#
# Table name: cs_admin_audit_logs
# Database name: primary
#
#  id              :uuid             not null, primary key
#  action          :integer          not null
#  actor_email     :string           not null
#  after_value     :boolean          not null
#  before_value    :boolean
#  feature_key     :string           not null
#  feature_type    :integer          not null
#  reason          :text             not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  actor_user_id   :uuid             not null
#  batch_id        :uuid
#  organization_id :uuid             not null
#  rollback_of_id  :uuid
#
# Indexes
#
#  idx_cs_audit_actor_created                    (actor_user_id,created_at DESC)
#  idx_cs_audit_batch                            (batch_id)
#  idx_cs_audit_feature_created                  (feature_key,created_at DESC)
#  idx_cs_audit_org_created                      (organization_id,created_at DESC)
#  index_cs_admin_audit_logs_on_actor_user_id    (actor_user_id)
#  index_cs_admin_audit_logs_on_organization_id  (organization_id)
#  index_cs_admin_audit_logs_on_rollback_of_id   (rollback_of_id)
#
# Foreign Keys
#
#  fk_rails_...  (actor_user_id => users.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (rollback_of_id => cs_admin_audit_logs.id)
#

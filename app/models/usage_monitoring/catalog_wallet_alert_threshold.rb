# frozen_string_literal: true

module UsageMonitoring
  class CatalogWalletAlertThreshold < ApplicationRecord
    include ThresholdRecord

    belongs_to :organization
    belongs_to :plan_wallet_alert, class_name: "UsageMonitoring::PlanWalletAlert", optional: true, inverse_of: :thresholds
    belongs_to :catalog_wallet_alert, class_name: "UsageMonitoring::CatalogWalletAlert", optional: true, inverse_of: :thresholds

    validates_with ParentPresenceValidator, parents: %i[plan_wallet_alert catalog_wallet_alert], error: :exactly_one_owner_required
  end
end

# == Schema Information
#
# Table name: usage_monitoring_catalog_wallet_alert_thresholds
# Database name: primary
#
#  id                      :uuid             not null, primary key
#  code                    :string
#  notify_on               :string           default(["triggered"]), not null, is an Array
#  recurring               :boolean          default(FALSE), not null
#  value                   :decimal(30, 5)   not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  catalog_wallet_alert_id :uuid
#  organization_id         :uuid             not null
#  plan_wallet_alert_id    :uuid
#
# Indexes
#
#  idx_catalog_wallet_alert_thresholds_catalog_recurring_unique  (catalog_wallet_alert_id,recurring) UNIQUE WHERE (recurring IS TRUE)
#  idx_catalog_wallet_alert_thresholds_catalog_wallet_alert_id   (catalog_wallet_alert_id) WHERE (catalog_wallet_alert_id IS NOT NULL)
#  idx_catalog_wallet_alert_thresholds_organization_id           (organization_id)
#  idx_catalog_wallet_alert_thresholds_plan_recurring_unique     (plan_wallet_alert_id,recurring) UNIQUE WHERE (recurring IS TRUE)
#  idx_catalog_wallet_alert_thresholds_plan_wallet_alert_id      (plan_wallet_alert_id) WHERE (plan_wallet_alert_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_wallet_alert_id => usage_monitoring_catalog_wallet_alerts.id) ON DELETE => cascade
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_wallet_alert_id => usage_monitoring_plan_wallet_alerts.id) ON DELETE => cascade
#

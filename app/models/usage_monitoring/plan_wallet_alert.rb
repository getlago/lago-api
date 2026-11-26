# frozen_string_literal: true

module UsageMonitoring
  class PlanWalletAlert < ApplicationRecord
    include CatalogWalletAlertSettings

    belongs_to :plan_wallet, -> { with_discarded }, inverse_of: :alerts

    has_many :thresholds,
      class_name: "UsageMonitoring::CatalogWalletAlertThreshold",
      dependent: :delete_all,
      inverse_of: :plan_wallet_alert
  end
end

# == Schema Information
#
# Table name: usage_monitoring_plan_wallet_alerts
# Database name: primary
#
#  id              :uuid             not null, primary key
#  alert_type      :enum             not null
#  code            :string           not null
#  name            :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#  plan_wallet_id  :uuid             not null
#
# Indexes
#
#  idx_plan_wallet_alerts_alert_type_unique  (plan_wallet_id,alert_type) UNIQUE
#  idx_plan_wallet_alerts_code_unique        (plan_wallet_id,code) UNIQUE
#  idx_plan_wallet_alerts_organization_id    (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_wallet_id => plan_wallets.id)
#

# frozen_string_literal: true

module UsageMonitoring
  class CatalogWalletAlert < ApplicationRecord
    include CatalogWalletAlertSettings

    belongs_to :catalog_wallet, -> { with_discarded }, inverse_of: :alerts

    has_many :thresholds,
      class_name: "UsageMonitoring::CatalogWalletAlertThreshold",
      dependent: :delete_all,
      inverse_of: :catalog_wallet_alert
    has_many :all_triggered_alerts,
      class_name: "UsageMonitoring::CatalogWalletTriggeredAlert",
      inverse_of: :alert

    def watches_wallet?
      true
    end

    # Before the ongoing balance is first computed its column holds a default, while with no usage deducted yet the
    # ongoing balance is the balance itself
    def find_value(catalog_wallet)
      if ongoing_balance? && catalog_wallet.last_ongoing_balance_sync_at?
        catalog_wallet.ongoing_balance_cents
      else
        catalog_wallet.balance_cents
      end
    end
  end
end

# == Schema Information
#
# Table name: usage_monitoring_catalog_wallet_alerts
# Database name: primary
#
#  id                :uuid             not null, primary key
#  alert_type        :enum             not null
#  code              :string           not null
#  last_processed_at :datetime
#  name              :string
#  previous_value    :decimal(30, 5)
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  catalog_wallet_id :uuid             not null
#  organization_id   :uuid             not null
#
# Indexes
#
#  idx_catalog_wallet_alerts_alert_type_unique  (catalog_wallet_id,alert_type) UNIQUE
#  idx_catalog_wallet_alerts_code_unique        (catalog_wallet_id,code) UNIQUE
#  idx_catalog_wallet_alerts_organization_id    (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_wallet_id => catalog_wallets.id)
#  fk_rails_...  (organization_id => organizations.id)
#

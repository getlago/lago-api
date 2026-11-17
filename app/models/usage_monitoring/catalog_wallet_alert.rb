# frozen_string_literal: true

module UsageMonitoring
  class CatalogWalletAlert < ApplicationRecord
    include CatalogWalletAlertSettings

    belongs_to :catalog_wallet, -> { with_discarded }, inverse_of: :alerts
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

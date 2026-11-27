# frozen_string_literal: true

module UsageMonitoring
  class CatalogWalletTriggeredAlert < ApplicationRecord
    include TriggeredAlertRecord

    enum :alert_type, CatalogWalletAlertSettings::ALERT_TYPES, validate: true

    belongs_to :organization
    belongs_to :catalog_wallet, -> { with_discarded }
    belongs_to :alert,
      class_name: "UsageMonitoring::CatalogWalletAlert",
      foreign_key: :catalog_wallet_alert_id,
      optional: true,
      inverse_of: :all_triggered_alerts

    # Alerts are deleted for good: the history keeps which alert it was once the alert is gone
    before_validation :copy_alert, on: :create, if: :alert

    def alertable=(alertable)
      case alertable
      when CatalogWallet then self.catalog_wallet = alertable
      else raise ArgumentError, "unsupported alertable: #{alertable.class}"
      end
    end

    private

    def copy_alert
      self.alert_code = alert.code
      self.alert_name = alert.name
      self.alert_type = alert.alert_type
    end
  end
end

# == Schema Information
#
# Table name: usage_monitoring_catalog_wallet_triggered_alerts
# Database name: primary
#
#  id                      :uuid             not null, primary key
#  alert_code              :string           not null
#  alert_name              :string
#  alert_type              :enum             not null
#  crossed_thresholds      :jsonb            not null
#  current_value           :decimal(30, 5)   not null
#  fully_resolved          :boolean
#  in_alarm_thresholds     :jsonb
#  kind                    :enum             default("triggered"), not null
#  previous_value          :decimal(30, 5)   not null
#  resolution_reason       :enum
#  triggered_at            :datetime         not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  catalog_wallet_alert_id :uuid             not null
#  catalog_wallet_id       :uuid             not null
#  organization_id         :uuid             not null
#
# Indexes
#
#  idx_catalog_wallet_triggered_alerts_catalog_wallet_alert_id  (catalog_wallet_alert_id)
#  idx_catalog_wallet_triggered_alerts_organization_id          (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_wallet_id => catalog_wallets.id)
#  fk_rails_...  (organization_id => organizations.id)
#

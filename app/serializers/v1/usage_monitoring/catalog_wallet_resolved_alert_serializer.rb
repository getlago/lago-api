# frozen_string_literal: true

module V1
  module UsageMonitoring
    # The keys of the v1 object and of contract usage alerts, null where they don't apply, with the wallet's code and
    # currency: values are in that currency's cents
    class CatalogWalletResolvedAlertSerializer < ModelSerializer
      def serialize
        {
          lago_id: model.id,
          lago_organization_id: model.organization_id,
          lago_alert_id: model.catalog_wallet_alert_id,
          lago_subscription_id: nil,
          external_subscription_id: nil,
          lago_wallet_id: wallet.id,
          wallet_code: wallet.code,
          currency: wallet.currency,
          lago_contract_id: wallet.contract_id,
          external_contract_id: wallet.contract.external_id,
          product_code: nil,
          product_filter_code: nil,
          applies_to: nil,
          external_customer_id: wallet.customer.external_id,
          billable_metric_code: nil,
          alert_name:,
          alert_code: model.alert_code,
          alert_type: model.alert_type,
          current_value: model.current_value,
          previous_value: model.previous_value,
          recovered_thresholds: model.crossed_thresholds,
          in_alarm_thresholds: model.in_alarm_thresholds,
          fully_resolved: model.fully_resolved,
          reason: model.resolution_reason,
          resolved_at: model.triggered_at.iso8601
        }
      end

      private

      def wallet
        model.catalog_wallet
      end

      # Alerts are deleted for good: once the alert is gone, its history keeps the name it had
      def alert_name
        model.alert ? model.alert.name : model.alert_name
      end
    end
  end
end

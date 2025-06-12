# frozen_string_literal: true

module V1
  module UsageMonitoring
    class TriggeredAlertSerializer < ModelSerializer
      def serialize
        {
          lago_id: model.id,
          lago_organization_id: model.organization_id,
          lago_alert_id: alert.id,
          lago_subscription_id: model.subscription_id,
          subscription_external_id: alert.subscription_external_id,
          customer_external_id: model.subscription.customer.external_id,
          billable_metric_code: alert.billable_metric&.code,
          alert_name: alert.name,
          alert_code: alert.code,
          alert_type: alert.alert_type,
          current_value: model.current_value,
          previous_value: model.previous_value,
          crossed_thresholds: model.crossed_thresholds,
          triggered_at: model.triggered_at.iso8601
        }
      end

      private

      delegate :alert, to: :model
    end
  end
end

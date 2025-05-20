# frozen_string_literal: true

module V1
  module UsageMonitoring
    class TriggeredAlertSerializer < ModelSerializer
      def serialize
        {
          lago_id: model.id,
          lago_alert_id: model.alert.id,
          lago_subscription_id: model.subscription_id,
          billable_metric_code: model.alert.billable_metric&.code,
          alert_name: model.alert.name,
          alert_code: model.alert.code,
          alert_type: model.alert.alert_type,
          current_value: model.current_value,
          previous_value: model.previous_value,
          crossed_thresholds: model.crossed_thresholds,
          triggered_at: model.triggered_at.iso8601
        }
      end
    end
  end
end

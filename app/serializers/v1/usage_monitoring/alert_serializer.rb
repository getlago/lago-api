# frozen_string_literal: true

module V1
  module UsageMonitoring
    class AlertSerializer < ModelSerializer
      def serialize
        {
          lago_id: model.id,
          lago_organization_id: model.organization_id,
          subscription_external_id: model.subscription_external_id,
          billable_metric_code: model.billable_metric&.code,
          alert_type: model.alert_type,
          code: model.code,
          name: model.name,
          previous_value: model.previous_value,
          last_processed_at: model.last_processed_at&.iso8601,
          thresholds: formatted_thresholds,
          created_at: model.created_at&.iso8601,
          updated_at: model.updated_at&.iso8601,
          deleted_at: model.deleted_at&.iso8601
        }
      end

      private

      def formatted_thresholds
        model.thresholds.map do |threshold|
          {
            code: threshold.code,
            value: threshold.value,
            recurring: threshold.recurring
          }
        end
      end
    end
  end
end

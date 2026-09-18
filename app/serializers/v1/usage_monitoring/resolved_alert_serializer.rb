# frozen_string_literal: true

module V1
  module UsageMonitoring
    class ResolvedAlertSerializer < TriggeredAlertSerializer
      def serialize
        super.merge(
          in_alarm_thresholds: model.in_alarm_thresholds,
          fully_resolved: model.fully_resolved,
          resolved_at: model.triggered_at.iso8601
        )
      end
    end
  end
end

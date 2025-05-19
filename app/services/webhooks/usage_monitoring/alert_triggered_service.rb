# frozen_string_literal: true

module Webhooks
  module UsageMonitoring
    class AlertTriggeredService < Webhooks::BaseService
      def current_organization
        @current_organization ||= object.organization
      end

      def object_serializer
        ::V1::UsageMonitoring::TriggeredAlertSerializer.new(
          object,
          root_name: object_type
        )
      end

      def webhook_type
        "alert.triggered"
      end

      def object_type
        "triggered_alert"
      end
    end
  end
end

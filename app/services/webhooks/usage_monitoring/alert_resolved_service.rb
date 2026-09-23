# frozen_string_literal: true

module Webhooks
  module UsageMonitoring
    class AlertResolvedService < Webhooks::BaseService
      private

      def object_serializer
        ::V1::UsageMonitoring::ResolvedAlertSerializer.new(
          object,
          root_name: object_type
        )
      end

      def webhook_type
        "alert.resolved"
      end

      def object_type
        "triggered_alert"
      end
    end
  end
end

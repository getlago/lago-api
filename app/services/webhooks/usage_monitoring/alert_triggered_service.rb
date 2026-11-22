# frozen_string_literal: true

module Webhooks
  module UsageMonitoring
    class AlertTriggeredService < Webhooks::BaseService
      private

      def object_serializer
        serializer_class.new(object, root_name: object_type)
      end

      # Each alert family renders its own history rows
      def serializer_class
        case object
        when ::UsageMonitoring::CatalogWalletTriggeredAlert then ::V1::UsageMonitoring::CatalogWalletTriggeredAlertSerializer
        else ::V1::UsageMonitoring::TriggeredAlertSerializer
        end
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

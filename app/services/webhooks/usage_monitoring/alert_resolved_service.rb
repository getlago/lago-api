# frozen_string_literal: true

module Webhooks
  module UsageMonitoring
    class AlertResolvedService < Webhooks::BaseService
      private

      def object_serializer
        serializer_class.new(object, root_name: object_type)
      end

      # Each alert family renders its own history rows
      def serializer_class
        case object
        when ::UsageMonitoring::CatalogWalletTriggeredAlert then ::V1::UsageMonitoring::CatalogWalletResolvedAlertSerializer
        else ::V1::UsageMonitoring::ResolvedAlertSerializer
        end
      end

      def webhook_type
        "alert.resolved"
      end

      def object_type
        "resolved_alert"
      end
    end
  end
end

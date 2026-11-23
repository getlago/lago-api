# frozen_string_literal: true

module Webhooks
  module UsageMonitoring
    class AlertResolvedService < Webhooks::BaseService
      private

      # A catalog wallet alert keeps the v1 event and carries its v2 body, as catalog plans and invoices do
      def object_serializer
        if object.is_a?(::UsageMonitoring::CatalogWalletTriggeredAlert)
          ::V2::CatalogWalletResolvedAlertSerializer.new(object, root_name: object_type)
        else
          ::V1::UsageMonitoring::ResolvedAlertSerializer.new(object, root_name: object_type)
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

# frozen_string_literal: true

module Webhooks
  module UsageMonitoring
    class AlertTriggeredService < Webhooks::BaseService
      private

      # Catalog wallet and contract alerts keep the v1 event and carry their v2 body, as catalog plans and invoices do
      def object_serializer
        case object
        when ::UsageMonitoring::CatalogWalletTriggeredAlert
          ::V2::CatalogWalletTriggeredAlertSerializer.new(object, root_name: object_type)
        when ::UsageMonitoring::ContractTriggeredAlert
          ::V2::ContractTriggeredAlertSerializer.new(object, root_name: object_type)
        else
          ::V1::UsageMonitoring::TriggeredAlertSerializer.new(object, root_name: object_type)
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

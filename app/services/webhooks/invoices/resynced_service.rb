# frozen_string_literal: true

module Webhooks
  module Invoices
    class ResyncedService < Webhooks::BaseService
      include Webhooks::Invoices::ProductCatalogPayload

      private

      def v1_includes
        %i[customer billing_periods integration_customers subscriptions fees credits applied_taxes]
      end

      def webhook_type
        "invoice.resynced"
      end

      def object_type
        "invoice"
      end
    end
  end
end

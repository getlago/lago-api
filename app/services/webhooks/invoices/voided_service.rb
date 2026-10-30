# frozen_string_literal: true

module Webhooks
  module Invoices
    class VoidedService < Webhooks::BaseService
      include Webhooks::Invoices::ProductCatalogPayload

      private

      def v1_includes
        %i[customer billing_periods subscriptions fees credits applied_taxes]
      end

      def webhook_type
        "invoice.voided"
      end

      def object_type
        "invoice"
      end
    end
  end
end

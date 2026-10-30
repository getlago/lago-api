# frozen_string_literal: true

module Webhooks
  module Invoices
    class CreatedService < Webhooks::BaseService
      include Webhooks::Invoices::ProductCatalogPayload

      private

      def v1_includes
        %i[customer subscriptions billing_periods fees credits applied_taxes applied_invoice_custom_sections]
      end

      def webhook_type
        "invoice.created"
      end

      def object_type
        "invoice"
      end
    end
  end
end

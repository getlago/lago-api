# frozen_string_literal: true

module Webhooks
  module Invoices
    class PaymentOverdueService < Webhooks::BaseService
      include Webhooks::Invoices::ProductCatalogPayload

      private

      def v1_includes
        %i[customer fees applied_taxes]
      end

      def webhook_type
        "invoice.payment_overdue"
      end

      def object_type
        "invoice"
      end
    end
  end
end

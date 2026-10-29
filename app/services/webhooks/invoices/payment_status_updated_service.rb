# frozen_string_literal: true

module Webhooks
  module Invoices
    class PaymentStatusUpdatedService < Webhooks::BaseService
      include Webhooks::Invoices::ProductCatalogPayload

      private

      def v1_includes
        %i[customer fees]
      end

      def webhook_type
        "invoice.payment_status_updated"
      end

      def object_type
        "invoice"
      end
    end
  end
end

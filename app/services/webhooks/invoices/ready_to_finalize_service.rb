# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Webhooks
  module Invoices
    class ReadyToFinalizeService < Webhooks::BaseService
      private

      def object_serializer
        ::V1::InvoiceSerializer.new(
          object,
          root_name: "invoice",
          includes: %i[customer subscriptions billing_periods fees credits applied_taxes error_details]
        )
      end

      def webhook_type
        "invoice.ready_to_finalize"
      end

      def object_type
        "invoice"
      end
    end
  end
end

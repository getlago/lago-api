# frozen_string_literal: true

module Webhooks
  module Invoices
    class ReadyToFinalizeService < Webhooks::BaseService
      include Webhooks::Invoices::ProductCatalogPayload

      private

      def v1_includes
        %i[customer subscriptions billing_periods fees credits applied_taxes error_details]
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

# frozen_string_literal: true

module Webhooks
  module Invoices
    class DeletedService < Webhooks::BaseService
      include Webhooks::Invoices::ProductCatalogPayload

      private

      def v1_includes
        %i[customer billing_periods subscriptions fees credits applied_taxes]
      end

      def webhook_type
        "invoice.deleted"
      end

      def object_type
        "invoice"
      end
    end
  end
end

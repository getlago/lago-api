# frozen_string_literal: true

module Webhooks
  module Invoices
    class GeneratedService < Webhooks::BaseService
      include Webhooks::Invoices::ProductCatalogPayload

      private

      def v1_includes
        %i[customer]
      end

      def webhook_type
        "invoice.generated"
      end

      def object_type
        "invoice"
      end
    end
  end
end

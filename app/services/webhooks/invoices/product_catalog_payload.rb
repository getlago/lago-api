# frozen_string_literal: true

module Webhooks
  module Invoices
    # A catalog invoice keeps the v1 event names but carries the v2 body.
    module ProductCatalogPayload
      private

      def object_serializer
        if object.product_catalog?
          ::V2::InvoiceSerializer.new(object, root_name: "invoice", includes: ::V2::InvoiceSerializer.webhook_includes)
        else
          ::V1::InvoiceSerializer.new(object, root_name: "invoice", includes: v1_includes)
        end
      end
    end
  end
end

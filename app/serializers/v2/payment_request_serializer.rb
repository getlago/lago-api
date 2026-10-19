# frozen_string_literal: true

module V2
  class PaymentRequestSerializer < ::V1::PaymentRequestSerializer
    # `contract_fees` lets `Invoice#product_catalog?` classify each invoice without a query, and
    # `organization` serves the v1 payload of legacy invoices.
    PRELOADS = [
      :customer,
      {invoices: [:contract_fees, :billing_entity, :customer, :organization, {file_attachment: :blob}, {xml_file_attachment: :blob}]}
    ].freeze

    # The credit note offsets of every invoice on the page, in one query.
    def self.preload_collection(payment_requests)
      ::Invoice.preload_aggregations(payment_requests.flat_map(&:invoices), :offset_amount_cents)
    end

    private

    def invoices
      {
        invoices: model.invoices.map do |invoice|
          serializer = invoice.product_catalog? ? ::V2::InvoiceSerializer : ::V1::InvoiceSerializer
          serializer.new(invoice).serialize
        end
      }
    end
  end
end

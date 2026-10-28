# frozen_string_literal: true

module Api
  module V2
    class PaymentReceiptsController < Api::V2::BaseController
      cursor_paginated_index(PaymentReceipt)
      serializable_with ::V2::PaymentReceiptSerializer

      # Receipts of legacy invoices are served by v1: on v2 they do not exist.
      def index
        result = ::PaymentReceiptsQuery.call(
          organization: current_organization,
          pagination: cursor,
          filters: {invoice_id: params[:lago_invoice_id], product_catalog: true}
        )

        if result.success?
          render_payment_receipts(result.payment_receipts.preload(::V2::PaymentReceiptSerializer::PRELOADS))
        else
          render_error_response(result)
        end
      end

      def show
        payment_receipt = current_organization.payment_receipts.find_by(id: params[:id])

        if payment_receipt
          render_payment_receipt(payment_receipt)
        else
          not_found_error(resource: "payment_receipt")
        end
      end

      private

      def filter_errors(filters)
        super(filters.transform_keys(invoice_id: :lago_invoice_id))
      end

      def resource_name
        "payment_receipt"
      end
    end
  end
end

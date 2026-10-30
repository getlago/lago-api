# frozen_string_literal: true

module Api
  module V2
    class PaymentReceiptsController < Api::V2::BaseController
      cursor_paginated_index(PaymentReceipt)
      date_range_filtered_index(:created_at)
      serializable_with ::V2::PaymentReceiptSerializer

      def index
        result = ::PaymentReceiptsQuery.call(
          organization: current_organization,
          pagination: cursor,
          filters: params.permit(:invoice_id).to_h.symbolize_keys.merge(date_range_filters)
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

      def resource_name
        "payment_receipt"
      end
    end
  end
end

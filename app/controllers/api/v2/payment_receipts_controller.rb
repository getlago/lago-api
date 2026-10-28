# frozen_string_literal: true

module Api
  module V2
    class PaymentReceiptsController < Api::V2::BaseController
      serializable_with ::V2::PaymentReceiptSerializer

      # Receipts of legacy invoices are served by v1: on v2 they do not exist.
      def show
        payment_receipt = current_organization.payment_receipts.product_catalog.find_by(id: params[:id])

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

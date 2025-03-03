# frozen_string_literal: true

module Api
  module V1
    class PaymentReceiptsController < Api::BaseController
      def index
        result = PaymentReceiptsQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters: index_filters
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.payment_receipts,
              ::V1::PaymentReceiptSerializer,
              collection_name: resource_name.pluralize,
              meta: pagination_metadata(result.payment_receipts)
            )
          )
        else
          render_error_response(result)
        end
      end

      def show
        payment_receipt = PaymentReceipt.where(organization: current_organization).find_by(id: params[:id])
        return not_found_error(resource: resource_name) unless payment_receipt

        render_payment_receipt(payment_receipt)
      end

      private

      def index_filters
        params.permit(:invoice_id)
      end

      def render_payment_receipt(payment_receipt)
        render(
          json: ::V1::PaymentReceiptSerializer.new(
            payment_receipt,
            root_name: resource_name
          )
        )
      end

      def resource_name
        "payment_receipt"
      end
    end
  end
end

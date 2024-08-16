# frozen_string_literal: true

module Api
  module V1
    class PaymentRequestsController < Api::BaseController
      def create
        result = PaymentRequests::CreateService.call(
          organization: current_organization,
          params: create_params.to_h.deep_symbolize_keys
        )

        if result.success?
          render(json: ::V1::PaymentRequestSerializer.new(result.payment_request, root_name: "payment_request"))
        else
          render_error_response(result)
        end
      end

      def index
        result = PaymentRequestsQuery.call(
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
              result.payment_requests.preload(:customer, payment_requestable: :invoices),
              ::V1::PaymentRequestSerializer,
              collection_name: "payment_requests",
              meta: pagination_metadata(result.payment_requests),
              includes: %i[customer invoices]
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      def create_params
        params.require(:payment_request).permit(
          :email,
          :external_customer_id,
          :lago_invoice_ids
        )
      end

      def index_filters
        params.permit(:external_customer_id)
      end
    end
  end
end

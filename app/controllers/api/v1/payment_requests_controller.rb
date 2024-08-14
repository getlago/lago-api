# frozen_string_literal: true

module Api
  module V1
    class PaymentRequestsController < Api::BaseController
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

      def index_filters
        params.permit(:external_customer_id)
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    module Customers
      class PaymentRequestsController < BaseController
        def index
          result = PaymentRequestsQuery.call(
            organization: current_organization,
            pagination: {
              page: params[:page],
              limit: params[:per_page] || PER_PAGE
            },
            filters: params.permit(:payment_status).merge(external_customer_id: customer.external_id)
          )

          if result.success?
            render(
              json: ::CollectionSerializer.new(
                result.payment_requests.preload(:customer, :invoices),
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

        def resource_name
          "payment_request"
        end
      end
    end
  end
end

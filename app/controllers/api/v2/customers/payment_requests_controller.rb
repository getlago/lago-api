# frozen_string_literal: true

module Api
  module V2
    module Customers
      class PaymentRequestsController < BaseController
        cursor_paginated_index(PaymentRequest)
        serializable_with ::V2::PaymentRequestSerializer

        def index
          result = ::PaymentRequestsQuery.call(
            organization: current_organization,
            pagination: cursor,
            filters: {external_customer_id: customer.external_id}
          )

          if result.success?
            render_payment_requests(result.payment_requests.preload(::V2::PaymentRequestSerializer::PRELOADS))
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

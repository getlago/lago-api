# frozen_string_literal: true

module Api
  module V2
    module Customers
      class PaymentsController < BaseController
        cursor_paginated_index(Payment)
        serializable_with ::V2::PaymentSerializer

        def index
          result = ::PaymentsQuery.call(
            organization: current_organization,
            pagination: cursor,
            # The id rather than the external one, which a deleted customer may share.
            filters: {customer_id: customer.id}
          )

          if result.success?
            render_payments(result.payments.preload(::V2::PaymentSerializer::PRELOADS))
          else
            render_error_response(result)
          end
        end

        private

        def resource_name
          "payment"
        end
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    module Customers
      class PaymentsController < BaseController
        def index
          result = PaymentsQuery.call(
            organization: current_organization,
            pagination: {
              page: params[:page],
              limit: params[:per_page] || PER_PAGE
            },
            filters: params.permit(:invoice_id).merge(external_customer_id: customer.external_id)
          )

          if result.success?
            render(
              json: ::CollectionSerializer.new(
                result.payments,
                ::V1::PaymentSerializer,
                collection_name: resource_name.pluralize,
                meta: pagination_metadata(result.payments)
              )
            )
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

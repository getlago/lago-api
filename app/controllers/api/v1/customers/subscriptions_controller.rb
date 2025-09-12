# frozen_string_literal: true

module Api
  module V1
    module Customers
      class SubscriptionsController < BaseController
        def index
          result = SubscriptionsQuery.call(
            organization: current_organization,
            pagination: {
              page: params[:page],
              limit: params[:per_page] || PER_PAGE
            },
            filters: index_filters.merge(external_customer_id: customer.external_id)
          )

          if result.success?
            render(
              json: ::CollectionSerializer.new(
                result.subscriptions,
                ::V1::SubscriptionSerializer,
                collection_name: "subscriptions",
                meta: pagination_metadata(result.subscriptions)
              )
            )
          else
            render_error_response(result)
          end
        end

        private

        def index_filters
          filters = params.permit(:plan_code, status: [])
          filters[:status] = ["active"] if filters[:status].blank?
          filters
        end

        def resource_name
          "subscription"
        end
      end
    end
  end
end

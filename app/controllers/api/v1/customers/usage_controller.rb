# frozen_string_literal: true

module Api
  module V1
    module Customers
      class UsageController < Api::BaseController
        def current
          result = ::Invoices::CustomerUsageService
            .call(
              nil,
              customer_id: params[:customer_external_id],
              subscription_id: params[:external_subscription_id],
              organization_id: current_organization.id
            )

          if result.success?
            render(
              json: ::V1::Customers::UsageSerializer.new(
                result.usage,
                root_name: "customer_usage",
                includes: %i[charges_usage]
              )
            )
          else
            render_error_response(result)
          end
        end

        def past
          result = PastUsageQuery.call(
            organization: current_organization,
            pagination: BaseQuery::Pagination.new(
              page: params[:page],
              limit: params[:per_page] || PER_PAGE
            ),
            filters: BaseQuery::Filters.new(past_usage_filters)
          )

          if result.success?
            render(
              json: ::CollectionSerializer.new(
                result.usage_periods,
                ::V1::Customers::PastUsageSerializer,
                collection_name: "usage_periods",
                meta: pagination_metadata(result),
                includes: %i[charges_usage]
              )
            )
          else
            render_error_response(result)
          end
        end

        private

        def past_usage_filters
          params.permit(
            :external_subscription_id,
            :billable_metric_code,
            :periods_count
          ).merge(
            external_customer_id: params[:customer_external_id]
          )
        end
      end
    end
  end
end

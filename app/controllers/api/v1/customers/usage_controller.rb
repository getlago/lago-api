# frozen_string_literal: true

module Api
  module V1
    module Customers
      class UsageController < Api::BaseController
        def current
          apply_taxes = ActiveModel::Type::Boolean.new.cast(params.fetch(:apply_taxes, true))
          full_usage = ActiveModel::Type::Boolean.new.cast(params.fetch(:full_usage, false))
          charge = find_charge_for_filter(params).presence
          result = ::Invoices::CustomerUsageService
            .with_external_ids(
              customer_external_id: params[:customer_external_id],
              external_subscription_id: params[:external_subscription_id],
              organization_id: current_organization.id,
              apply_taxes:,
              filter_by_charge: charge,
              filter_by_group: params[:filter_by_group]&.to_unsafe_h,
              full_usage: full_usage
            ).call

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
            pagination: {
              page: params[:page],
              limit: params[:per_page] || PER_PAGE
            },
            filters: past_usage_filters
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

        def resource_name
          "customer_usage"
        end

        def find_charge_for_filter(params)
          if params[:filter_by_charge_code].present?
            current_organization.charges.find_by!(code: params[:filter_by_charge_code])
          elsif params[:filter_by_charge_id].present?
            current_organization.charges.find_by!(id: params[:filter_by_charge_id])
          end
        end
      end
    end
  end
end

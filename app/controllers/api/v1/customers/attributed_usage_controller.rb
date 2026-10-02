# frozen_string_literal: true

module Api
  module V1
    module Customers
      class AttributedUsageController < Api::BaseController
        DEFAULT_PER_PAGE = UsageAttributions::QueryService::DEFAULT_LIMIT
        MAX_PER_PAGE = UsageAttributions::QueryService::MAX_LIMIT
        QUERY_LIMIT_ERRORS = %w[too_many_groups query_timeout memory_limit_exceeded].freeze

        Page = Data.define(:total_count, :current_page, :limit_value)

        before_action :ensure_feature_flag!

        def show
          return not_found_error(resource: "customer") unless customer
          return not_found_error(resource: "subscription") unless subscription
          return validation_errors(errors: params_errors) if params_errors.any?
          return not_found_error(resource: "charge") unless charges_found?

          result = ::UsageAttributions::QueryService.call(
            subscription:,
            group_by: params[:group_by],
            filters: filters_params,
            from_datetime: parsed_datetime(:from_datetime),
            to_datetime: parsed_datetime(:to_datetime),
            charges: selected_charges,
            split_charge: selected_split_charge,
            search: params[:search_term],
            basis: params[:basis] || "units",
            limit: per_page,
            offset: (page - 1) * per_page
          )

          if result.success?
            render(
              json: {
                attributed_usage: ::V1::AttributedUsageSerializer.new(result, subscription:, group_by: params[:group_by]).serialize,
                meta: pagination_metadata(Page.new(total_count: result.groups_count, current_page: page, limit_value: per_page))
              }
            )
          else
            render_query_error(result)
          end
        end

        private

        def customer
          @customer ||= current_organization.customers.find_by(external_id: params[:customer_external_id])
        end

        def subscription
          @subscription ||= customer.active_subscriptions.find_by(external_id: params[:external_subscription_id])
        end

        def params_errors
          @params_errors ||= {
            from_datetime: datetime_errors(:from_datetime),
            to_datetime: datetime_errors(:to_datetime),
            page: (["value_is_out_of_range"] unless page&.positive?),
            per_page: (["value_is_out_of_range"] unless per_page&.between?(1, MAX_PER_PAGE))
          }.compact_blank
        end

        def datetime_errors(name)
          (params[name].blank? || parsed_datetime(name)) ? [] : ["invalid_date"]
        end

        def parsed_datetime(name)
          return if params[name].blank?

          Utils::Datetime.parse_iso8601(params[name])&.to_time&.in_time_zone
        end

        def page
          Integer(params[:page] || 1, exception: false)
        end

        def per_page
          Integer(params[:per_page] || DEFAULT_PER_PAGE, exception: false)
        end

        # filters[team]=eng&filters[model][]=opus&filters[model][]=haiku
        def filters_params
          params.permit(filters: {})[:filters]&.to_h || {}
        end

        def charge_codes
          Array(params[:charge_codes]).map(&:to_s).uniq if params.key?(:charge_codes)
        end

        def selected_charges
          @selected_charges ||= subscription.plan.charges.where(code: charge_codes).to_a if charge_codes
        end

        def selected_split_charge
          return if params[:split_charge_code].blank?

          @selected_split_charge ||= subscription.plan.charges.find_by(code: params[:split_charge_code])
        end

        def charges_found?
          all_charges_found = charge_codes.nil? || selected_charges.size == charge_codes.size
          split_charge_found = params[:split_charge_code].blank? || selected_split_charge.present?

          all_charges_found && split_charge_found
        end

        def render_query_error(result)
          if result.error.is_a?(BaseService::ServiceFailure) && QUERY_LIMIT_ERRORS.include?(result.error.code)
            render(
              json: {status: 422, error: "Unprocessable Entity", code: result.error.code},
              status: :unprocessable_content
            )
          else
            render_error_response(result)
          end
        end

        def ensure_feature_flag!
          forbidden_error(code: "feature_unavailable") unless current_organization.account_tree_enabled?
        end

        def resource_name
          "attributed_usage"
        end
      end
    end
  end
end

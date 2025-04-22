# frozen_string_literal: true

module Api
  module V1
    module DataApi
      class UsagesController < Api::V1::DataApi::BaseController
        def index
          # @result = ::DataApi::UsagesService.call(current_organization, **filters)

          # if @result.success?
          if true
            render_result(@result)
          else
            render_error_response(@result)
          end
        end

        private

        def filters
          {
            time_granularity: params[:time_granularity],
            currency: params[:currency],
            from_date: params[:from_date],
            to_date: params[:to_date],
            customer_type: params[:customer_type],
            external_customer_id: params[:external_customer_id],
            customer_country: params[:customer_country],
            external_subscription_id: params[:external_subscription_id],
            plan_code: params[:plan_code],
            billable_metric_code: params[:billable_metric_code],
            grouped_by: params[:grouped_by],
            filter_values: params[:filter_values]
          }
        end
      end
    end
  end
end

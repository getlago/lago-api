# frozen_string_literal: true

module Api
  module V1
    class SubscriptionsController < Api::BaseController
      def create
        subscription_service = Subscriptions::CreateService.new
        result = subscription_service.create_from_api(
          organization: current_organization,
          params: create_params,
        )

        if result.success?
          render(
            json: ::V1::SubscriptionSerializer.new(
              result.subscription,
              root_name: 'subscription',
            ),
          )
        else
          validation_errors(result)
        end
      end

      # NOTE: We can't destroy a subscription, it will terminate it
      def terminate
        result = Subscriptions::TerminateService.new
          .terminate_from_api(
            organization: current_organization,
            customer_id: params[:customer_id],
          )

        if result.success?
          render(
            json: ::V1::SubscriptionSerializer.new(
              result.subscription,
              root_name: 'subscription',
            ),
          )
        else
          validation_errors(result)
        end
      end

      private

      def create_params
        params.require(:subscription)
          .permit(:customer_id, :plan_code)
      end
    end
  end
end

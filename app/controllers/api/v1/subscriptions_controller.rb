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
            subscription_id: params[:subscription_id],
          )

        if result.success?
          render(
            json: ::V1::SubscriptionSerializer.new(
              result.subscription,
              root_name: 'subscription',
            ),
          )
        else
          render_error_response(result)
        end
      end

      def update
        service = Subscriptions::UpdateService.new

        result = service.update(**{
          id: params[:id],
          name: update_params[:name]
        })

        if result.success?
          render(
            json: ::V1::SubscriptionSerializer.new(
              result.subscription,
              root_name: 'subscription',
              ),
            )
        else
          render_error_response(result)
        end
      end

      private

      def create_params
        params.require(:subscription)
          .permit(:customer_id, :plan_code, :name, :subscription_id)
      end

      def update_params
        params.require(:subscription).permit(:name)
      end
    end
  end
end

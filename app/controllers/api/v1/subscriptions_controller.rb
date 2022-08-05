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
            subscription_id: params[:id]
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

        result = service.update_from_api(
          organization: current_organization,
          id: params[:id],
          params: update_params
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

      def index
        customer = Customer.find_by(customer_id: params[:customer_id])

        return not_found_error unless customer

        subscriptions = customer.active_subscriptions
                                .page(params[:page])
                                .per(params[:per_page] || PER_PAGE)

        render(
          json: ::CollectionSerializer.new(
            subscriptions,
            ::V1::SubscriptionSerializer,
            collection_name: 'subscriptions',
            meta: pagination_metadata(subscriptions),
          ),
        )
      end

      private

      def create_params
        params.require(:subscription)
          .permit(:customer_id, :plan_code, :name, :subscription_id, :unique_id, :billing_time)
      end

      def update_params
        params.require(:subscription).permit(:name)
      end
    end
  end
end

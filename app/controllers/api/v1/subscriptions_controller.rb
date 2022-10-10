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
          render_error_response(result)
        end
      end

      # NOTE: We can't destroy a subscription, it will terminate it
      def terminate
        result = Subscriptions::TerminateService.new
          .terminate_from_api(
            organization: current_organization,
            external_id: params[:external_id],
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
          external_id: params[:external_id],
          params: update_params,
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
        customer = current_organization.customers.find_by(external_id: params[:external_customer_id])

        return not_found_error(resource: 'customer') unless customer

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
          .permit(:external_customer_id, :plan_code, :name, :external_id, :billing_time, :subscription_date)
      end

      def update_params
        params.require(:subscription).permit(:name, :subscription_date)
      end
    end
  end
end

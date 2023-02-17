# frozen_string_literal: true

module Api
  module V1
    class SubscriptionsController < Api::BaseController
      def create
        customer = Customer.find_or_initialize_by(
          external_id: create_params[:external_customer_id]&.strip,
          organization_id: current_organization.id,
        )

        plan = Plan.find_by(
          code: create_params[:plan_code],
          organization_id: current_organization.id,
        )

        result = Subscriptions::CreateService.call(
          customer:,
          plan:,
          params: SubscriptionLegacyInput.new(
            current_organization,
            create_params,
          ).create_input,
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
        subscription = current_organization.subscriptions.active.find_by(external_id: params[:external_id])
        result = Subscriptions::TerminateService.call(subscription:)

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

        result = service.update(
          subscription: current_organization.subscriptions.find_by(external_id: params[:external_id]),
          args: SubscriptionLegacyInput.new(
            current_organization,
            update_params,
          ).update_input,
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
          .permit(
            :external_customer_id,
            :plan_code,
            :name,
            :external_id,
            :billing_time,
            :subscription_date,
            :subscription_at,
          )
      end

      def update_params
        params.require(:subscription).permit(:name, :subscription_date, :subscription_at)
      end
    end
  end
end

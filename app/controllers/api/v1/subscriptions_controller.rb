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

      def create_with_override
        plan_params = Plans::PrepareForOverrideService
          .new(current_organization, overridden_plan_code_params[:overridden_plan_code])
          .call(plan_params: create_with_override_plan_params)

        override_service = Subscriptions::OverrideService.new

        result = override_service.call_from_api(
          organization: current_organization,
          plan_args: plan_params,
          subscription_args: create_with_override_subscription_params,
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
          .permit(:external_customer_id, :plan_code, :name, :external_id, :billing_time)
      end

      def update_params
        params.require(:subscription).permit(:name)
      end

      def create_with_override_subscription_params
        params.require(:subscription).permit(
          :external_customer_id,
          :name,
          :external_id,
          :billing_time,
        )
      end

      def overridden_plan_code_params
        params.require(:subscription).permit(:overridden_plan_code)
      end

      def create_with_override_plan_params
        params.require(:subscription).require(:plan).permit(
          :amount_cents,
          :amount_currency,
          :trial_period,
          charges: [:id, :charge_model],
        ).tap do |permitted_params|
          # NOTE: Charges properties can have 2 different formats
          # - An array if the charge model need many ranges (ie: graduated)
          # - A hash if other cases (ie: standard)
          (permitted_params[:charges] || []).each_with_index do |permitted_charge, idx|
            permitted_charge[:properties] = if params[:subscription][:plan][:charges][idx][:properties].is_a?(Array)
              params[:subscription][:plan][:charges][idx][:properties].map(&:permit!)
            else
              params[:subscription][:plan][:charges][idx][:properties].permit!
            end
          end
        end
      end
    end
  end
end

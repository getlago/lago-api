# frozen_string_literal: true

module Api
  module V2
    class SubscriptionsController < Api::BaseController
      # Terminates a subscription in the new engine: ends every product item it holds
      # and emits each one's final prorated cycle. Separate from the legacy v1
      # subscription terminate (which bills charges / issues credit notes) — the two
      # engines run side by side.
      def terminate
        subscription = current_organization.subscriptions.find_by(
          external_id: params[:external_id], status: :active
        )
        return not_found_error(resource: "subscription") unless subscription

        result = ::V2::Subscriptions::TerminateService.call(
          subscription:,
          terminated_at: params[:terminated_at] || Time.current
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.subscription_product_items,
              ::V1::SubscriptionProductItemSerializer,
              collection_name: "subscription_product_items"
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      def resource_name
        "subscription"
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V2
    class SubscriptionsController < Api::BaseController
      def index
        filters = params.permit(:plan_code, :external_customer_id, :external_id, status: [])
        filters[:status] = ["active"] if filters[:status].blank?

        result = ::SubscriptionsQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters:
        )

        if result.success?
          subscriptions = result.subscriptions.includes(:plan, customer: :billing_entity)

          render(
            json: ::CollectionSerializer.new(
              subscriptions,
              ::V2::SubscriptionSerializer,
              collection_name: "subscriptions",
              meta: pagination_metadata(subscriptions)
            )
          )
        else
          render_error_response(result)
        end
      end

      def show
        subscription = current_organization.subscriptions
          .order("terminated_at DESC NULLS FIRST, started_at DESC")
          .find_by(
            external_id: params[:external_id],
            status: params[:status] || :active
          )
        return not_found_error(resource: "subscription") unless subscription

        render(
          json: ::V2::SubscriptionSerializer.new(
            subscription,
            root_name: "subscription",
            includes: %i[subscription_rate_cards]
          )
        )
      end

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
              result.subscription_rate_cards,
              ::V1::SubscriptionRateCardSerializer,
              collection_name: "subscription_rate_cards"
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

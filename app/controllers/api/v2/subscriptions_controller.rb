# frozen_string_literal: true

module Api
  module V2
    class SubscriptionsController < Api::BaseController
      include Api::RequiresProductCatalog

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

          # One grouped query instead of one COUNT per row in the serializer.
          applied_rate_cards_counts = SubscriptionRateCard.current_and_scheduled
            .where(subscription_id: subscriptions.map(&:id))
            .group(:subscription_id)
            .count

          render(
            json: ::CollectionSerializer.new(
              subscriptions,
              ::V2::SubscriptionSerializer,
              collection_name: "subscriptions",
              meta: pagination_metadata(subscriptions),
              applied_rate_cards_counts:
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
            includes: %i[applied_rate_cards]
          )
        )
      end

      private

      def resource_name
        "subscription"
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V2
    class SubscriptionRateCardsController < Api::BaseController
      def create
        result = ::SubscriptionRateCards::CreateService.call(
          subscription: find_subscription,
          params: create_params.to_h.deep_symbolize_keys
        )

        if result.success?
          render_subscription_rate_card(result.subscription_rate_card)
        else
          render_error_response(result)
        end
      end

      def show
        subscription_rate_card = find_subscription_rate_card

        return not_found_error(resource: "subscription_rate_card") unless subscription_rate_card

        render_subscription_rate_card(subscription_rate_card)
      end

      def update
        subscription_rate_card = find_subscription_rate_card
        result = ::SubscriptionRateCards::UpdateService.call(
          subscription_rate_card:,
          params: update_params.to_h.deep_symbolize_keys
        )

        if result.success?
          render_subscription_rate_card(result.subscription_rate_card)
        else
          render_error_response(result)
        end
      end

      def destroy
        subscription_rate_card = find_subscription_rate_card
        result = ::SubscriptionRateCards::DestroyService.call(subscription_rate_card:)

        if result.success?
          render_subscription_rate_card(result.subscription_rate_card)
        else
          render_error_response(result)
        end
      end

      def index
        return not_found_error(resource: "subscription") unless find_subscription

        result = ::SubscriptionRateCardsQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters: {external_subscription_id: params[:subscription_external_id]}
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.subscription_rate_cards,
              ::V1::SubscriptionRateCardSerializer,
              collection_name: "subscription_rate_cards",
              meta: pagination_metadata(result.subscription_rate_cards)
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      # All routes are nested under the subscription: an entry is addressed by
      # its natural key — the subscription external id and the rate card code
      # (unique together thanks to the one-card-per-slice rule) — so consumers
      # never persist Lago ids.
      def find_subscription_rate_card
        subscription = current_organization.subscriptions.order(created_at: :desc)
          .find_by(external_id: params[:subscription_external_id])
        return nil unless subscription

        subscription.subscription_rate_cards.joins(:rate_card).find_by(rate_cards: {code: params[:code]})
      end

      # A pending subscription can share its external_id with a past one;
      # prefer the pending one (the only editable state), then the latest.
      def find_subscription
        subscriptions = current_organization.subscriptions.where(external_id: params[:subscription_external_id])
        subscriptions.pending.first || subscriptions.order(created_at: :desc).first
      end

      def create_params
        params.require(:subscription_rate_card).permit(
          :rate_card_code, :units, :started_at, :billing_anchor_date,
          rate_phases: [
            :position,
            :name,
            :billing_interval_cycle_count,
            {rate_override: [
              :rate_model,
              :min_amount_cents,
              :billing_interval_count,
              :billing_interval_unit,
              :pricing_unit_conversion_rate,
              {rate_properties: {}}
            ]}
          ]
        )
      end

      def update_params
        params.require(:subscription_rate_card).permit(:units, :started_at, :billing_anchor_date)
      end

      def render_subscription_rate_card(subscription_rate_card)
        render(json: ::V1::SubscriptionRateCardSerializer.new(subscription_rate_card, root_name: "subscription_rate_card"))
      end

      def resource_name
        "subscription_rate_card"
      end
    end
  end
end

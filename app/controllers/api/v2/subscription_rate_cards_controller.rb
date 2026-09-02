# frozen_string_literal: true

module Api
  module V2
    class SubscriptionRateCardsController < Api::BaseController
      include Api::RequiresProductCatalog

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

        return not_found_error(resource: "applied_rate_card") unless subscription_rate_card

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
        subscription = find_subscription
        return not_found_error(resource: "subscription") unless subscription

        # Scope by id, not external_id: several subscriptions can share an
        # external_id over time and the list must match the version the nested
        # routes address.
        result = ::SubscriptionRateCardsQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters: {subscription_id: subscription.id}
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.subscription_rate_cards,
              ::V1::SubscriptionRateCardSerializer,
              collection_name: "applied_rate_cards",
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
        subscription = find_subscription
        return nil unless subscription

        entries = subscription.applied_rate_cards.joins(:rate_card).where(rate_cards: {code: params[:code]})
        # The version in force now, or the upcoming one: a card authored on a
        # pending subscription starts in the future and must stay addressable
        # during its authoring window.
        entries.active_at(Time.current).first || entries.current_and_scheduled.order(:started_at).first
      end

      # A pending subscription can share its external_id with a past one;
      # prefer the pending one (the only editable state), then the latest.
      def find_subscription
        subscriptions = current_organization.subscriptions.where(external_id: params[:subscription_external_id])
        subscriptions.pending.first || subscriptions.order(created_at: :desc).first
      end

      def create_params
        params.require(:applied_rate_card).permit(
          :rate_card_code, :units, :started_at, :billing_anchor_date,
          rate_phases: [
            :code,
            :position,
            :name,
            :billing_interval_cycle_count,
            {rate_override: [
              :rate_model,
              :min_amount_cents,
              :billing_interval_count,
              :billing_interval_unit,
              :pricing_unit_conversion_rate,
              # Structural card fields pass through so the override service can
              # reject them explicitly instead of strong params dropping them.
              :billing_timing,
              :currency,
              :proration,
              :display_on_invoice,
              :regroup_paid_fees,
              :wallet_targetable,
              :applied_pricing_unit_code,
              {rate_properties: {}}
            ]}
          ]
        )
      end

      def update_params
        params.require(:applied_rate_card).permit(:units, :apply_units, :started_at, :billing_anchor_date)
      end

      def render_subscription_rate_card(subscription_rate_card)
        render(json: ::V1::SubscriptionRateCardSerializer.new(subscription_rate_card, root_name: "applied_rate_card"))
      end

      def resource_name
        "subscription_rate_card"
      end
    end
  end
end

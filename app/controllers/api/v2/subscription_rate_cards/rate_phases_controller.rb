# frozen_string_literal: true

module Api
  module V2
    module SubscriptionRateCards
      class RatePhasesController < Api::BaseController
        include Api::RequiresProductCatalog

        def index
          return not_found_error(resource: "applied_rate_card") unless subscription_rate_card

          render_rate_phases(subscription_rate_card.rate_phases.order(:position))
        end

        def create
          return not_found_error(resource: "applied_rate_card") unless subscription_rate_card

          result = ::RatePhases::CreateService.call(
            subscription_rate_card:,
            params: phase_params.to_h.deep_symbolize_keys
          )

          if result.success?
            render_rate_phase(result.rate_phase)
          else
            render_error_response(result)
          end
        end

        def update
          rate_phase = find_rate_phase
          return not_found_error(resource: "rate_phase") unless rate_phase

          result = ::RatePhases::UpdateService.call(
            rate_phase:,
            params: phase_params.to_h.deep_symbolize_keys
          )

          if result.success?
            render_rate_phase(result.rate_phase)
          else
            render_error_response(result)
          end
        end

        def destroy
          rate_phase = find_rate_phase
          return not_found_error(resource: "rate_phase") unless rate_phase

          result = ::RatePhases::DestroyService.call(rate_phase:)

          if result.success?
            render_rate_phase(result.rate_phase)
          else
            render_error_response(result)
          end
        end

        private

        def subscription_rate_card
          @subscription_rate_card ||= begin
            subscription = current_organization.subscriptions.order(created_at: :desc)
              .find_by(external_id: params[:subscription_external_id])
            subscription&.applied_rate_cards&.active_at(Time.current)&.joins(:rate_card)&.find_by(rate_cards: {code: params[:applied_rate_card_code]})
          end
        end

        def find_rate_phase
          subscription_rate_card&.rate_phases&.find_by(code: params[:code])
        end

        def phase_params
          params.require(:rate_phase).permit(
            :code, :position, :name, :billing_interval_cycle_count,
            rate_override: [
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
            ]
          )
        end

        def render_rate_phase(rate_phase)
          render(json: ::V1::RatePhaseSerializer.new(rate_phase, root_name: "rate_phase"))
        end

        def render_rate_phases(rate_phases)
          render(
            json: ::CollectionSerializer.new(
              rate_phases,
              ::V1::RatePhaseSerializer,
              collection_name: "rate_phases"
            )
          )
        end

        def resource_name
          "subscription_rate_card"
        end
      end
    end
  end
end

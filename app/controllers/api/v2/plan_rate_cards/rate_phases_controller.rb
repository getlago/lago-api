# frozen_string_literal: true

module Api
  module V2
    module PlanRateCards
      class RatePhasesController < Api::BaseController
        def index
          return not_found_error(resource: "plan_rate_card") unless plan_rate_card

          render_rate_phases(plan_rate_card.rate_phases.order(:position))
        end

        def replace
          return not_found_error(resource: "plan_rate_card") unless plan_rate_card

          result = ::RatePhases::ReplaceService.call(
            plan_rate_card:,
            phases_params: replace_params
          )

          if result.success?
            render_rate_phases(result.rate_phases)
          else
            render_error_response(result)
          end
        end

        private

        def plan_rate_card
          @plan_rate_card ||= begin
            plan = current_organization.plans.parents.find_by(code: params[:plan_code])
            plan&.plan_rate_cards&.joins(:rate_card)&.find_by(rate_cards: {code: params[:rate_card_code]})
          end
        end

        def replace_params
          params
            .permit(rate_phases: [
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
            ])
            .to_h
            .deep_symbolize_keys
            .fetch(:rate_phases, [])
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
          "plan_rate_card"
        end
      end
    end
  end
end

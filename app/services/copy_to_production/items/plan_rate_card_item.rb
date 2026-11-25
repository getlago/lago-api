# frozen_string_literal: true

module CopyToProduction
  module Items
    # A rate card of a plan, with its phases: copied along with its plan, or on its own into the live plan with its
    # plan's code. It is known in a plan by the code of its rate card, which is reused by code or copied before it.
    class PlanRateCardItem < BaseItem
      PHASE_ATTRIBUTES = %i[code position name billing_interval_cycle_count].freeze
      RATE_OVERRIDE_ATTRIBUTES = %i[
        rate_model rate_properties min_amount_cents billing_interval_count billing_interval_unit
        pricing_unit_conversion_rate
      ].freeze

      def find_source(id)
        PlanRateCard.where(organization: sandbox).find_by(id:)
      end

      def find_existing(source)
        production.catalog_plans.find_by(code: source.catalog_plan.code)&.applied_rate_cards&.joins(:rate_card)
          &.find_by(rate_cards: {code: source.rate_card.code, deleted_at: nil})
      end

      def parent(source)
        ["catalog_plan", source.catalog_plan]
      end

      def dependencies(source)
        [*product_dependencies(source.rate_card.product), ["rate_card", source.rate_card]]
      end

      def copy!(source, resolved)
        PlanRateCards::CreateService.call!(
          catalog_plan: resolved.fetch(["catalog_plan", source.catalog_plan_id]),
          params: {
            rate_card_code: source.rate_card.code,
            units: source.units,
            rate_phases: source.rate_phases.sort_by(&:position).map { phase_params(it) }.presence
          }
        ).plan_rate_card
      end

      private

      # Storage adds each tier's lower bound, which the create service refuses: it takes tiers as the API shows them.
      def phase_params(phase)
        override = phase.rate_override&.slice(*RATE_OVERRIDE_ATTRIBUTES)&.symbolize_keys
        override[:rate_properties] = RateProperties.present(override[:rate_properties]) if override

        phase.slice(*PHASE_ATTRIBUTES).symbolize_keys.merge(rate_override: override)
      end
    end
  end
end

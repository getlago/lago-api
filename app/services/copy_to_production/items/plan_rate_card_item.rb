# frozen_string_literal: true

module CopyToProduction
  module Items
    # A rate card of a plan, with its phases: copied along with its plan, or on its own into the live plan with its
    # plan's code. It is known in a plan by the code of its rate card, which is reused by code or copied before it.
    class PlanRateCardItem < BaseItem
      PRELOADS = [
        {rate_phases: :rate_override},
        {rate_card: [{product: [:product_category, *ProductItem::OWN_PRELOADS]}, *(RateCardItem::PRELOADS - [:product])]}
      ].freeze
      PHASE_ATTRIBUTES = %i[code position name billing_interval_cycle_count].freeze
      RATE_OVERRIDE_ATTRIBUTES = %i[
        rate_model rate_properties min_amount_cents billing_interval_count billing_interval_unit
        pricing_unit_conversion_rate
      ].freeze

      def find_source(id)
        PlanRateCard.where(organization: sandbox).includes(:catalog_plan, *PRELOADS).find_by(id:)
      end

      def find_existing(source)
        live_plan(source)&.applied_rate_cards&.joins(:rate_card)
          &.find_by(rate_cards: {code: source.rate_card.code, deleted_at: nil})
      end

      def parents(source)
        [["catalog_plan", source.catalog_plan]]
      end

      def dependencies(source)
        [*product_dependencies(source.rate_card.product), ["rate_card", source.rate_card]]
      end

      # As PlanRateCards::CreateService: a plan with contracts cannot change its pricing, it bills cards of its own
      # currency, and it prices a product, or one of its filters, once. The card read is the one the copy attaches: the
      # live card with its code, or the sandbox card it copies. A card the live plan already has answers
      # value_already_exist before this.
      def refusal(source)
        plan = live_plan(source)
        return "plan_locked" if plan&.attached_to_contracts?

        card = attached_card(source)
        return "currency_does_not_match" if card.currency != (plan || source.catalog_plan).currency

        "copy_to_production_already_priced" if plan && priced_slices(plan, except: card.code).include?(slice(card))
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

      def active_subscriptions_count(source)
        live_plan(source)&.contracts&.active&.count
      end

      def unique_indexes
        {"index_plan_rate_cards_on_catalog_plan_id_and_rate_card_id" => :code}
      end

      private

      def live_plan(source)
        @live_plans ||= {}
        code = source.catalog_plan.code
        return @live_plans[code] if @live_plans.key?(code)

        @live_plans[code] = production.catalog_plans.find_by(code:)
      end

      def attached_card(source)
        production.rate_cards.includes(:product, :product_filter).find_by(code: source.rate_card.code) || source.rate_card
      end

      def priced_slices(plan, except:)
        plan.applied_rate_cards.includes(rate_card: [:product, :product_filter])
          .reject { it.rate_card.code == except }.map { slice(it.rate_card) }
      end

      def slice(rate_card)
        [rate_card.product.code, rate_card.product_filter&.code]
      end

      def phase_params(phase)
        phase.slice(*PHASE_ATTRIBUTES).symbolize_keys.merge(
          rate_override: phase.rate_override&.slice(*RATE_OVERRIDE_ATTRIBUTES)&.symbolize_keys
        )
      end
    end
  end
end

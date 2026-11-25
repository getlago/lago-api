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
      # value_already_exist before this. A plan copied whole attaches the cards of its other rate cards, and a reused
      # live card keeps its own filter, so two of them can price the same slice.
      def refusal(source)
        plan = live_plan(source)
        return "plan_locked" if plan&.attached_to_contracts?

        card = attached_card(source)
        return "currency_does_not_match" if card.currency != (plan || source.catalog_plan).currency

        slices = plan ? priced_slices(plan, except: card.code) : sibling_slices(source, except: card.code)
        return "copy_to_production_already_priced" if slices.include?(slice(card))

        "copy_to_production_rate_mismatch" if override_mismatch?(source, card)
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
        @attached_cards ||= {}
        code = source.rate_card.code
        return @attached_cards[code] if @attached_cards.key?(code)

        @attached_cards[code] = production.rate_cards.includes(:product, :product_filter).find_by(code:) || source.rate_card
      end

      # The cards the copy attaches for the other rate cards of the sandbox plan, as CatalogPlanItem#children lists them.
      # Each card is a step of its own, so the live cards are read in one query rather than one per sibling.
      def sibling_slices(source, except:)
        siblings = source.catalog_plan.applied_rate_cards.includes(rate_card: [:product, :product_filter])
          .reject { it.rate_card.discarded? || it.rate_card.code == except }.map(&:rate_card)
        live_cards = production.rate_cards.includes(:product, :product_filter)
          .where(code: siblings.map(&:code)).index_by(&:code)

        siblings.map { slice(live_cards[it.code] || it) }
      end

      def priced_slices(plan, except:)
        plan.applied_rate_cards.includes(rate_card: [:product, :product_filter])
          .reject { it.rate_card.code == except }.map { slice(it.rate_card) }
      end

      def slice(rate_card)
        [rate_card.product.code, rate_card.product_filter&.code]
      end

      # As RateOverrides::CreateService reads each override on the card the copy attaches, in the product it lands in.
      def override_mismatch?(source, card)
        card = landing_card(card) if card.organization_id == sandbox.id

        source.rate_phases.filter_map(&:rate_override).any? do |override|
          (card.applied_pricing_unit_code.present? && override.pricing_unit_conversion_rate.blank?) ||
            (override.min_amount_cents.to_i.positive? && card.advance?) ||
            RateCardRates::ModelCompatibility.error_code(rate_model: override.rate_model, rate_card: card).present?
        end
      end

      # Storage adds each tier's lower bound, which the create service refuses: it takes tiers as the API shows them.
      def phase_params(phase)
        override = phase.rate_override&.slice(*RATE_OVERRIDE_ATTRIBUTES)&.symbolize_keys
        override[:rate_properties] = RateProperties.present(override[:rate_properties]) if override

        phase.slice(*PHASE_ATTRIBUTES).symbolize_keys.merge(rate_override: override)
      end
    end
  end
end

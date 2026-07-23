# frozen_string_literal: true

module PlanRateCards
  class CreateService < BaseService
    Result = BaseResult[:plan_rate_card]

    def initialize(plan:, params:)
      @plan = plan
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "plan") unless plan

      # A plan with subscriptions is immutable: pricing changes go through a new
      # plan and a subscription migration.
      if plan.attached_to_subscriptions?
        return result.single_validation_failure!(field: :plan, error_code: "plan_locked")
      end

      rate_card = organization.rate_cards.find_by(code: params[:rate_card_code])
      return result.not_found_failure!(resource: "rate_card") unless rate_card

      # One card per pricing slice: a plan may hold several cards of the same
      # item only when they cover different filter slices (default + EU, ...).
      # A second card on the same (item, filter) pair would price the same
      # events twice.
      if slice_already_priced?(rate_card)
        return result.single_validation_failure!(field: :rate_card, error_code: "product_item_slice_already_priced")
      end

      # Fees are billed in the card currency and the invoice in the plan
      # currency; a mismatch must fail at configuration time, not on the
      # first invoice.
      if rate_card.currency != plan.amount_currency
        return result.single_validation_failure!(field: :currency, error_code: "currencies_does_not_match")
      end

      ActiveRecord::Base.transaction do
        plan_rate_card = plan.plan_rate_cards.create!(
          organization:,
          rate_card:,
          units: params[:units]
        )

        RatePhases::CreateService.call!(plan_rate_card:, params: {position: 1})

        result.plan_rate_card = plan_rate_card
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :plan, :params

    def slice_already_priced?(rate_card)
      plan.plan_rate_cards.joins(:rate_card).exists?(
        rate_cards: {
          product_item_id: rate_card.product_item_id,
          product_item_filter_id: rate_card.product_item_filter_id
        }
      )
    end

    def organization
      plan.organization
    end
  end
end

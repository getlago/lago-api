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

      # On a legacy plan the config would be silently ignored by the v1 engine.
      unless plan.product_catalog?
        return result.single_validation_failure!(field: :plan, error_code: "legacy_plan")
      end

      rate_card = organization.rate_cards.find_by(code: params[:rate_card_code])
      return result.not_found_failure!(resource: "rate_card") unless rate_card

      # Fees are billed in the card currency and the invoice in the plan
      # currency; a mismatch must fail at configuration time, not on the
      # first invoice.
      if rate_card.currency != plan.amount_currency
        return result.single_validation_failure!(field: :currency, error_code: "currency_does_not_match")
      end

      plan.with_lock do
        # One card per pricing slice: a plan may hold several cards of the same
        # item only when they cover different filter slices (default + EU, ...).
        if slice_already_priced?(rate_card)
          return result.single_validation_failure!(field: :rate_card, error_code: slice_error_code(rate_card))
        end

        plan_rate_card = plan.applied_rate_cards.create!(
          organization:,
          rate_card:,
          units: params[:units]
        )

        # Phases can be authored atomically with the entry: a provided sequence
        # goes through the same validations as the single-phase ops (an explicit
        # empty list is rejected there) and a failure rolls the whole create
        # back. Omitted or null, the entry starts on a single default terminal
        # phase.
        if params.key?(:rate_phases) && !params[:rate_phases].nil?
          RatePhases::ReplaceService.call!(plan_rate_card:, phases_params: params[:rate_phases])
        else
          RatePhases::CreateService.call!(plan_rate_card:, params: {code: "default", position: 1})
        end

        result.plan_rate_card = plan_rate_card
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :plan, :params

    def slice_error_code(rate_card)
      if rate_card.product_filter_id
        "product_filter_already_priced"
      else
        "product_already_priced"
      end
    end

    def slice_already_priced?(rate_card)
      plan.applied_rate_cards.joins(:rate_card).exists?(
        rate_cards: {
          product_id: rate_card.product_id,
          product_filter_id: rate_card.product_filter_id
        }
      )
    end

    def organization
      plan.organization
    end
  end
end

# frozen_string_literal: true

module SubscriptionRateCards
  # Attaches a rate card directly to a subscription (sales-led flow). The
  # entry is authored on the subscription itself and is only editable while
  # the subscription is pending: once active, its pricing is signed.
  class CreateService < BaseService
    Result = BaseResult[:subscription_rate_card]

    def initialize(subscription:, params:)
      @subscription = subscription
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "subscription") unless subscription

      unless subscription.pending?
        return result.single_validation_failure!(field: :subscription, error_code: "subscription_locked")
      end

      rate_card = organization.rate_cards.find_by(code: params[:rate_card_code])
      return result.not_found_failure!(resource: "rate_card") unless rate_card

      # One card per pricing slice, mirroring the plan-side rule: a second card
      # on the same (item, filter) pair would price the same events twice.
      if slice_already_priced?(rate_card)
        return result.single_validation_failure!(field: :rate_card, error_code: "product_item_slice_already_priced")
      end

      # Same rule as on plans: the invoice is issued in the subscription's
      # plan currency, so a directly-attached card must match it. A mismatch
      # fails at configuration time, not on the first invoice.
      if rate_card.currency != subscription.plan.amount_currency
        return result.single_validation_failure!(field: :currency, error_code: "currencies_does_not_match")
      end

      started_at = params[:started_at].presence || Time.current

      ActiveRecord::Base.transaction do
        subscription_rate_card = subscription.subscription_rate_cards.create!(
          organization:,
          rate_card:,
          units: params[:units],
          started_at:,
          billing_anchor_date: params[:billing_anchor_date].presence || started_at.to_date,
          next_billing_at: started_at
        )

        # Phases can be authored atomically with the entry: a provided sequence
        # goes through the same validations as the PUT (contiguous positions,
        # indefinite phase last) and a failure rolls the whole create back.
        # Omitted, the entry starts on a single default terminal phase.
        if params[:rate_phases].present?
          RatePhases::ReplaceService.call!(subscription_rate_card:, phases_params: params[:rate_phases])
        else
          RatePhases::CreateService.call!(subscription_rate_card:, params: {position: 1})
        end

        result.subscription_rate_card = subscription_rate_card
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :subscription, :params

    def slice_already_priced?(rate_card)
      subscription.subscription_rate_cards.joins(:rate_card).exists?(
        rate_cards: {
          product_item_id: rate_card.product_item_id,
          product_item_filter_id: rate_card.product_item_filter_id
        }
      )
    end

    def organization
      subscription.organization
    end
  end
end

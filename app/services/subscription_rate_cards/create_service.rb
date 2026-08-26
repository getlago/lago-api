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
        return result.single_validation_failure!(field: :rate_card, error_code: slice_error_code(rate_card))
      end

      # Same rule as on plans: the invoice is issued in the subscription's
      # plan currency, so a directly-attached card must match it. A mismatch
      # fails at configuration time, not on the first invoice.
      if rate_card.currency != subscription.plan.amount_currency
        return result.single_validation_failure!(field: :currency, error_code: "currency_does_not_match")
      end

      # The column is a date: a malformed value would cast to nil, fall
      # through the NOT NULL constraint and crash instead of failing cleanly.
      if params[:billing_anchor_date].present? && !Utils::Datetime.valid_format?(params[:billing_anchor_date])
        return result.single_validation_failure!(field: :billing_anchor_date, error_code: "value_is_invalid")
      end

      # Same default as plan materialization: the card starts with the
      # subscription, not on the day it was authored — a pending subscription
      # starts in the future.
      started_at = params[:started_at].presence || subscription.started_at || subscription.subscription_at

      ActiveRecord::Base.transaction do
        subscription_rate_card = subscription.applied_rate_cards.create!(
          organization:,
          rate_card:,
          units: params[:units],
          started_at:,
          # A card added mid-subscription follows the subscription's anchor, not
          # the day it was added, so it invoices alongside the existing cards.
          billing_anchor_date: params[:billing_anchor_date].presence || subscription.effective_billing_anchor_date,
          next_billing_at: started_at
        )

        # Phases can be authored atomically with the entry: a provided sequence
        # goes through the same validations as the PUT (contiguous positions,
        # indefinite phase last) and a failure rolls the whole create back.
        # Omitted, the entry starts on a single default terminal phase.
        # Same gate as on plans: an explicit empty array is a meaningful input
        # and must be rejected by the replace validations, not silently swapped
        # for the default phase.
        if params.key?(:rate_phases) && !params[:rate_phases].nil?
          RatePhases::ReplaceService.call!(subscription_rate_card:, phases_params: params[:rate_phases])
        else
          RatePhases::CreateService.call!(subscription_rate_card:, params: {code: "default", position: 1})
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

    def slice_error_code(rate_card)
      if rate_card.product_filter_id
        "product_filter_already_priced"
      else
        "product_already_priced"
      end
    end

    def slice_already_priced?(rate_card)
      subscription.applied_rate_cards.joins(:rate_card).exists?(
        rate_cards: {
          product_id: rate_card.product_id,
          product_filter_id: rate_card.product_filter_id
        }
      )
    end

    def organization
      subscription.organization
    end
  end
end

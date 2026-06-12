# frozen_string_literal: true

module RateCards
  class UpdateService < BaseService
    Result = BaseResult[:rate_card]

    # Per the spec, currency and pricing unit are locked once any rate exists on
    # the card: create a new card instead. Other structural fields stay mutable
    # until the card is linked to a plan, which is handled by the plan workstream.
    LOCKED_WITH_RATES = %i[currency applied_pricing_unit_code].freeze

    def initialize(rate_card:, params:)
      @rate_card = rate_card
      @params = params.to_h.with_indifferent_access
      super
    end

    activity_loggable(
      action: "rate_card.updated",
      record: -> { rate_card }
    )

    def call
      return result.not_found_failure!(resource: "rate_card") unless rate_card

      if rate_card.rates.exists?
        locked_field = LOCKED_WITH_RATES.find { params.key?(it) && params[it] != rate_card[it] }
        if locked_field
          return result.single_validation_failure!(field: locked_field, error_code: "not_editable_with_rates")
        end
      end

      assign_attributes
      rate_card.save!

      result.rate_card = rate_card
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :rate_card, :params

    def assign_attributes
      rate_card.name = params[:name] if params.key?(:name)
      rate_card.description = params[:description] if params.key?(:description)
      rate_card.currency = params[:currency] if params.key?(:currency)
      rate_card.billing_timing = params[:billing_timing] if params.key?(:billing_timing)
      rate_card.proration = params[:proration] if params.key?(:proration)
      rate_card.display_on_invoice = params[:display_on_invoice] if params.key?(:display_on_invoice)
      rate_card.regroup_paid_fees = params[:regroup_paid_fees] if params.key?(:regroup_paid_fees)
      rate_card.applied_pricing_unit_code = params[:applied_pricing_unit_code] if params.key?(:applied_pricing_unit_code)
      rate_card.wallet_targetable = params[:wallet_targetable] if params.key?(:wallet_targetable)
    end
  end
end

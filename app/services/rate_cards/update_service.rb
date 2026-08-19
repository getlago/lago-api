# frozen_string_literal: true

module RateCards
  class UpdateService < BaseService
    include ValidatesBooleanParams

    Result = BaseResult[:rate_card]

    # Billing-semantic fields freeze once a rate exists — changing them would
    # alter what the existing rates mean; create a new card instead.
    LOCKED_WITH_RATES = %i[currency applied_pricing_unit_code billing_timing proration regroup_paid_fees display_on_invoice wallet_targetable].freeze

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

      # An explicit null means none — the column is NOT NULL.
      if params.key?(:regroup_paid_fees) && params[:regroup_paid_fees].nil?
        params[:regroup_paid_fees] = "none"
      end

      boolean_failure = boolean_params_failure
      return boolean_failure if boolean_failure

      if params[:wallet_targetable] && !rate_card.organization.events_targeting_wallets_enabled?
        return result.single_validation_failure!(field: :wallet_targetable, error_code: "feature_unavailable")
      end

      if params[:applied_pricing_unit_code].present? && !rate_card.organization.pricing_units.exists?(code: params[:applied_pricing_unit_code])
        return result.single_validation_failure!(field: :applied_pricing_unit_code, error_code: "value_is_invalid")
      end

      if rate_card.rates.exists?
        locked_field = LOCKED_WITH_RATES.find { params.key?(it) && params[it] != rate_card[it] }
        if locked_field
          return result.single_validation_failure!(field: locked_field, error_code: "not_editable_with_rates")
        end
      end

      # An attachment is created only when the card and its plan share a
      # currency, so the currency freezes once the card is attached.
      if params.key?(:currency) && params[:currency] != rate_card.currency && rate_card.attached_to_plan_or_subscription?
        return result.single_validation_failure!(field: :currency, error_code: "attached_to_plan_or_subscription")
      end

      # Code is identity: editable until the card is in a plan or subscription.
      if params.key?(:code) && params[:code]&.strip != rate_card.code && rate_card.attached_to_plan_or_subscription?
        return result.single_validation_failure!(field: :code, error_code: "attached_to_plan_or_subscription")
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
      rate_card.code = params[:code]&.strip if params.key?(:code)
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

# frozen_string_literal: true

module RateCards
  class UpdateService < BaseService
    include ValidatesBooleanParams

    Result = BaseResult[:rate_card]

    # Billing-semantic fields freeze once a rate exists — changing them would
    # alter what the existing rates mean; create a new card instead.
    LOCKED_WITH_RATES = %i[currency applied_pricing_unit_code billing_timing proration regroup_paid_fees display_on_invoice].freeze

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

      boolean_failure = boolean_params_failure
      return boolean_failure if boolean_failure

      if params[:applied_pricing_unit_code].present? && !rate_card.organization.pricing_units.exists?(code: params[:applied_pricing_unit_code])
        return result.single_validation_failure!(field: :applied_pricing_unit_code, error_code: "value_is_invalid")
      end

      if rate_card.rates.exists?
        locked_field = LOCKED_WITH_RATES.find { params.key?(it) && params[it] != rate_card[it] }
        if locked_field
          return result.single_validation_failure!(field: locked_field, error_code: "not_editable_with_rates")
        end
      end

      # Overrides on the card's plan and contract phases outlive its rates, and
      # prorated graduated billing needs whole tier bounds.
      if turning_on_proration? && decimal_graduated_override?
        return result.single_validation_failure!(field: :proration, error_code: "decimal_bound_not_allowed_with_proration")
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

      ActiveRecord::Base.transaction do
        assign_attributes
        rate_card.save!
        apply_taxes
      end

      result.rate_card = rate_card
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e.result.error)
    end

    private

    attr_reader :rate_card, :params

    def turning_on_proration?
      params.key?(:proration) && ActiveModel::Type::Boolean.new.cast(params[:proration]) && !rate_card.proration?
    end

    def decimal_graduated_override?
      phases = RatePhase.where(plan_rate_card_id: rate_card.plan_applied_rate_cards.select(:id))
        .or(RatePhase.where(contract_rate_card_id: rate_card.contract_applied_rate_cards.select(:id)))

      RateOverride.where(id: phases.select(:rate_override_id)).any? do |rate_override|
        Array(rate_override.rate_properties["graduated_ranges"]).any? do |range|
          range["to_value"].present? && !BigDecimal(range["to_value"].to_s).frac.zero?
        end
      end
    end

    def apply_taxes
      return unless params.key?(:tax_codes) && !params[:tax_codes].nil?

      RateCards::ApplyTaxesService.call!(rate_card:, tax_codes: params[:tax_codes])
    end

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
    end
  end
end

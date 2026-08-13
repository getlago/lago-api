# frozen_string_literal: true

module RateCardRates
  class UpdateService < BaseService
    Result = BaseResult[:rate_card_rate]

    # Terminated rates are frozen, active rates only accept new pricing values,
    # pending rates are fully editable. Frozen fields are rejected on presence:
    # sending one on an active rate is an error even with an unchanged value.
    FROZEN_ON_ACTIVE = %i[effective_from rate_model min_amount_cents billing_interval_count billing_interval_unit].freeze

    def initialize(rate_card_rate:, params:)
      @rate_card_rate = rate_card_rate
      @params = params.to_h.with_indifferent_access
      super
    end

    activity_loggable(
      action: "rate_card.updated",
      record: -> { rate_card_rate&.rate_card }
    )

    def call
      return result.not_found_failure!(resource: "rate_card_rate") unless rate_card_rate

      # On a card billed by subscriptions only pending rates stay editable:
      # the active rate prices live subscriptions, changes go through appends.
      if rate_card_rate.rate_card.attached_to_subscriptions? && !rate_card_rate.pending?
        return result.single_validation_failure!(field: :rate_card, error_code: "attached_to_subscriptions")
      end

      if rate_card_rate.terminated?
        return result.single_validation_failure!(field: :status, error_code: "terminated_rate_not_editable")
      end

      if rate_card_rate.active?
        frozen_field = FROZEN_ON_ACTIVE.find { params.key?(it) }
        if frozen_field
          return result.single_validation_failure!(field: frozen_field, error_code: "not_editable_on_active_rate")
        end
      end

      # Code is identity: editable until the card is in a plan or subscription.
      if params.key?(:code) && params[:code]&.strip != rate_card_rate.code && rate_card_rate.rate_card.attached_to_plan_or_subscription?
        return result.single_validation_failure!(field: :code, error_code: "attached_to_plan_or_subscription")
      end

      assign_attributes
      rate_card_rate.save!

      result.rate_card_rate = rate_card_rate
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :rate_card_rate, :params

    def assign_attributes
      rate_card_rate.code = params[:code]&.strip if params.key?(:code)
      rate_card_rate.effective_from = params[:effective_from] if params.key?(:effective_from)
      rate_card_rate.rate_model = params[:rate_model] if params.key?(:rate_model)
      rate_card_rate.rate_properties = params[:rate_properties] if params.key?(:rate_properties)
      rate_card_rate.min_amount_cents = params[:min_amount_cents] if params.key?(:min_amount_cents)
      rate_card_rate.billing_interval_count = params[:billing_interval_count] if params.key?(:billing_interval_count)
      rate_card_rate.billing_interval_unit = params[:billing_interval_unit] if params.key?(:billing_interval_unit)

      if params.key?(:applied_pricing_unit_conversion_rate)
        rate_card_rate.applied_pricing_unit_conversion_rate = params[:applied_pricing_unit_conversion_rate]
      end
    end
  end
end

# frozen_string_literal: true

module RateCards
  class CreateService < BaseService
    include ValidatesBooleanParams

    Result = BaseResult[:rate_card]

    def initialize(product:, params:)
      @product = product
      @params = params.to_h.with_indifferent_access
      super
    end

    activity_loggable(
      action: "rate_card.created",
      record: -> { result.rate_card }
    )

    def call
      return result.not_found_failure!(resource: "product") unless product

      # A JSON body can send a number or a boolean, which has no strip.
      unless params[:code].nil? || params[:code].is_a?(String)
        return result.single_validation_failure!(field: :code, error_code: "value_is_invalid")
      end

      boolean_failure = boolean_params_failure
      return boolean_failure if boolean_failure

      unless params[:rates].nil? || params[:rates].is_a?(Array)
        return result.single_validation_failure!(field: :rates, error_code: "value_is_invalid")
      end

      product_filter = nil
      if params[:product_filter_id].present?
        product_filter = product.filters.find_by(id: params[:product_filter_id])
        return result.not_found_failure!(resource: "product_filter") unless product_filter
      end

      if params[:applied_pricing_unit_code].present? && !organization.pricing_units.exists?(code: params[:applied_pricing_unit_code])
        return result.single_validation_failure!(field: :applied_pricing_unit_code, error_code: "value_is_invalid")
      end

      attributes = {
        organization:,
        product_filter:,
        name: params[:name],
        code: params[:code]&.strip,
        description: params[:description],
        currency: params[:currency],
        billing_timing: params[:billing_timing] || "arrears",
        applied_pricing_unit_code: params[:applied_pricing_unit_code]
      }
      # NOT NULL columns with DB defaults: only set when a value is given.
      attributes[:proration] = params[:proration] unless params[:proration].nil?
      attributes[:display_on_invoice] = params[:display_on_invoice] unless params[:display_on_invoice].nil?
      # Nullable: nil (omitted or explicit) stores NULL — the fee stays standalone.
      attributes[:regroup_paid_fees] = params[:regroup_paid_fees]

      ActiveRecord::Base.transaction do
        rate_card = product.rate_cards.create!(**attributes)

        apply_taxes(rate_card)
        create_rates(rate_card)

        result.rate_card = rate_card
        SendWebhookJob.perform_after_commit("rate_card.created", rate_card)
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e.result.error)
    end

    private

    attr_reader :product, :params

    def organization
      product&.organization
    end

    def apply_taxes(rate_card)
      return unless params.key?(:tax_codes) && !params[:tax_codes].nil?

      RateCards::ApplyTaxesService.call!(rate_card:, tax_codes: params[:tax_codes])
    end

    def create_rates(rate_card)
      (params[:rates] || []).each_with_index do |rate_params, index|
        RateCardRates::CreateService.call!(rate_card:, params: rate_params, emit_events: false)
      rescue BaseService::ValidationFailure => e
        result.fail_with_error!(e.remap(result) { BaseService::ValidationFailure.item_field(:rates, index, it) }).raise_if_error!
      end
    end
  end
end

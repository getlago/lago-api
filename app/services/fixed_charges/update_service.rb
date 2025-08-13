# frozen_string_literal: true

module FixedCharges
  class UpdateService < BaseService
    def initialize(fixed_charge:, params:, cascade_options: {})
      @fixed_charge = fixed_charge
      @params = params.to_h.deep_symbolize_keys
      @cascade_options = cascade_options
      @cascade = cascade_options[:cascade]

      super
    end

    def call
      return result.not_found_failure!(resource: "fixed_charge") unless fixed_charge
      return result if cascade && fixed_charge.charge_model != params[:charge_model]

      ActiveRecord::Base.transaction do
        fixed_charge.charge_model = params[:charge_model] unless plan.attached_to_subscriptions?
        # TODO: what should be cascaded, what - not?
        fixed_charge.invoice_display_name = params[:invoice_display_name]
        fixed_charge.units = params[:units]
        fixed_charge.prorated = params[:prorated]
        if !cascade || cascade_options[:equal_properties]
          properties = params.delete(:properties).presence || ChargeModels::BuildDefaultPropertiesService.call(
            params[:charge_model]
          )
          fixed_charge.properties = ChargeModels::FilterPropertiesService.call(chargeable: fixed_charge, properties:).properties
        end

        fixed_charge.save!
        result.fixed_charge = fixed_charge

        unless cascade
          tax_codes = params.delete(:tax_codes)
          if tax_codes && !plan.attached_to_subscriptions?
            taxes_result = FixedCharges::ApplyTaxesService.call(fixed_charge:, tax_codes:)
            taxes_result.raise_if_error!
          end
        end
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :fixed_charge, :params, :cascade_options, :cascade

    delegate :plan, to: :fixed_charge
  end
end

# frozen_string_literal: true

module Charges
  class OverrideService < BaseService
    def initialize(charge:, params:)
      @charge = charge
      @params = params

      super
    end

    def call
      return result unless License.premium?

      ActiveRecord::Base.transaction do
        new_charge = charge.dup.tap do |c|
          c.properties = params[:properties] if params.key?(:properties)
          c.min_amount_cents = params[:min_amount_cents] if params.key?(:min_amount_cents)
          c.invoice_display_name = params[:invoice_display_name] if params.key?(:invoice_display_name)
          c.group_properties = charge.group_properties.map(&:dup)
          c.plan_id = params[:plan_id]
        end
        new_charge.save!

        if params.key?(:group_properties)
          group_result = GroupProperties::CreateOrUpdateBatchService.call(
            charge: new_charge,
            properties_params: params[:group_properties],
          )
          return group_result if group_result.error
        end

        if params.key?(:tax_codes)
          taxes_result = Charges::ApplyTaxesService.call(charge: new_charge, tax_codes: params[:tax_codes])
          taxes_result.raise_if_error!
        end

        result.charge = new_charge
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :charge, :params
  end
end

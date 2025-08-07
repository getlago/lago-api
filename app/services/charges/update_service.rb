# frozen_string_literal: true

module Charges
  class UpdateService < BaseService
    def initialize(charge:, params:, cascade_options: {})
      @charge = charge
      @params = params.to_h.deep_symbolize_keys
      @cascade_options = cascade_options
      @cascade = cascade_options[:cascade]

      super
    end

    def call
      return result.not_found_failure!(resource: "charge") unless charge
      return result if cascade && charge.charge_model != params[:charge_model]

      ActiveRecord::Base.transaction do
        charge.charge_model = params[:charge_model] unless plan.attached_to_subscriptions?
        charge.invoice_display_name = params[:invoice_display_name] unless cascade

        # Make sure that pricing group keys are cascaded even if properties are overridden
        cascade_pricing_group_keys if cascade

        if !cascade || cascade_options[:equal_properties]
          properties = params.delete(:properties).presence || ChargeModels::BuildDefaultPropertiesService.call(
            params[:charge_model]
          )
          charge.properties = ChargeModels::FilterPropertiesService.call(chargeable: charge, properties:).properties
        end

        charge.save!

        AppliedPricingUnits::UpdateService.call!(
          charge:,
          cascade_options:,
          params: params.delete(:applied_pricing_unit).presence
        )

        filters = params.delete(:filters)
        unless filters.nil?
          ChargeFilters::CreateOrUpdateBatchService.call(
            charge:,
            filters_params: filters.map(&:with_indifferent_access),
            cascade_options:
          ).raise_if_error!
        end

        result.charge = charge

        # In cascade mode it is allowed only to change properties
        unless cascade
          tax_codes = params.delete(:tax_codes)
          if tax_codes
            taxes_result = Charges::ApplyTaxesService.call(charge:, tax_codes:)
            taxes_result.raise_if_error!
          end

          # NOTE: charges cannot be edited if plan is attached to a subscription
          unless plan.attached_to_subscriptions?
            invoiceable = params.delete(:invoiceable)
            min_amount_cents = params.delete(:min_amount_cents)

            charge.invoiceable = invoiceable if License.premium? && !invoiceable.nil?
            charge.min_amount_cents = min_amount_cents || 0 if License.premium?

            charge.update!(params)
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

    attr_reader :charge, :params, :cascade_options, :cascade

    delegate :plan, to: :charge

    def cascade_pricing_group_keys
      pricing_group_keys = params.dig(:properties, :pricing_group_keys) || params.dig(:properties, :grouped_by)

      if pricing_group_keys
        charge.properties["pricing_group_keys"] = pricing_group_keys
        charge.properties.delete("grouped_by")
      elsif charge.pricing_group_keys.present?
        charge.properties.delete("pricing_group_keys")
        charge.properties.delete("grouped_by")
      end
    end
  end
end

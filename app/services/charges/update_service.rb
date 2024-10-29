# frozen_string_literal: true

module Charges
  class UpdateService < BaseService
    def initialize(charge:, params:, options: {})
      @charge = charge
      @params = params
      @options = options
      @cascade = options[:cascade]

      super
    end

    def call
      return result.not_found_failure!(resource: 'charge') unless charge
      return result if cascade && charge.charge_model != params[:charge_model]

      ActiveRecord::Base.transaction do
        charge.charge_model = params[:charge_model] unless plan.attached_to_subscriptions?
        charge.invoice_display_name = params[:invoice_display_name] unless cascade

        if !cascade || options[:equal_properties]
          properties = params.delete(:properties).presence || Charges::BuildDefaultPropertiesService.call(
            params[:charge_model]
          )
          charge.properties = Charges::FilterChargeModelPropertiesService.call(charge:, properties:).properties
        end

        charge.save!

        filters = params.delete(:filters)
        unless filters.nil?
          ChargeFilters::CreateOrUpdateBatchService.call(
            charge:,
            filters_params: filters.map(&:with_indifferent_access),
            options:
          ).raise_if_error!
        end

        result.charge = charge

        # In cascade mode it is allowed only to change properties
        return result if cascade

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

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :charge, :params, :options, :cascade

    delegate :plan, to: :charge
  end
end

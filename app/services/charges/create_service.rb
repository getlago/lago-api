# frozen_string_literal: true

module Charges
  class CreateService < BaseService
    def initialize(plan:, params:)
      @plan = plan
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: 'plan') unless plan

      ActiveRecord::Base.transaction do
        charge = plan.charges.new(
          billable_metric_id: params[:billable_metric_id],
          invoice_display_name: params[:invoice_display_name],
          amount_currency: params[:amount_currency],
          charge_model: charge_model(params),
          pay_in_advance: params[:pay_in_advance] || false,
          prorated: params[:prorated] || false
        )

        properties = params[:properties].presence || Charges::BuildDefaultPropertiesService.call(charge.charge_model)
        charge.properties = Charges::FilterChargeModelPropertiesService.call(
          charge:,
          properties:
        ).properties

        if params[:filters].present?
          charge.save!
          ChargeFilters::CreateOrUpdateBatchService.call(
            charge:,
            filters_params: params[:filters].map(&:with_indifferent_access)
          ).raise_if_error!
        end

        if License.premium?
          charge.invoiceable = params[:invoiceable] unless params[:invoiceable].nil?
          charge.regroup_paid_fees = params[:regroup_paid_fees] if params.key?(:regroup_paid_fees)
          charge.min_amount_cents = params[:min_amount_cents] || 0
        end

        charge.save!

        if params[:tax_codes]
          taxes_result = Charges::ApplyTaxesService.call(charge:, tax_codes: params[:tax_codes])
          taxes_result.raise_if_error!
        end

        result.charge = charge
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :plan, :params

    def charge_model(params)
      model = params[:charge_model]&.to_sym
      return if model == :graduated_percentage && !License.premium?

      model
    end
  end
end

# frozen_string_literal: true

module FixedCharges
  class CreateService < BaseService
    def initialize(plan:, params:)
      @plan = plan
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: "plan") unless plan

      ActiveRecord::Base.transaction do
        fixed_charge = plan.fixed_charges.new(
          organization_id: plan.organization_id,
          add_on_id: params[:add_on_id],
          invoice_display_name: params[:invoice_display_name],
          charge_model: params[:charge_model],
          parent_id: params[:parent_id],
          pay_in_advance: params[:pay_in_advance] || false,
          prorated: params[:prorated] || false
        )

        properties = params[:properties].presence || FixedCharges::BuildDefaultPropertiesService.call(fixed_charge.charge_model)
        fixed_charge.properties = FixedCharges::FilterChargeModelPropertiesService.call(
          fixed_charge:,
          properties:
        ).properties

        fixed_charge.save!
        result.fixed_charge = fixed_charge
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :plan, :params
  end
end

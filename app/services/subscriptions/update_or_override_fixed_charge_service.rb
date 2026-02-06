# frozen_string_literal: true

module Subscriptions
  class UpdateOrOverrideFixedChargeService < BaseService
    include Concerns::PlanOverrideConcern

    Result = BaseResult[:fixed_charge]

    def initialize(subscription:, fixed_charge:, params:)
      @subscription = subscription
      @fixed_charge = fixed_charge
      @params = params

      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "subscription") unless subscription
      return result.not_found_failure!(resource: "fixed_charge") unless fixed_charge

      ActiveRecord::Base.transaction do
        target_plan = ensure_plan_override
        target_fixed_charge = find_or_create_fixed_charge_override(target_plan)

        result.fixed_charge = target_fixed_charge
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :subscription, :fixed_charge, :params

    def find_or_create_fixed_charge_override(target_plan)
      parent_fixed_charge = find_parent_fixed_charge
      existing_override = target_plan.fixed_charges.find_by(parent_id: parent_fixed_charge.id)

      if existing_override
        update_fixed_charge_override(existing_override)
      else
        create_fixed_charge_override(parent_fixed_charge, target_plan)
      end
    end

    def find_parent_fixed_charge
      if fixed_charge.parent_id
        fixed_charge.parent
      else
        fixed_charge
      end
    end

    def create_fixed_charge_override(parent_fixed_charge, target_plan)
      override_result = FixedCharges::OverrideService.call!(
        fixed_charge: parent_fixed_charge,
        params: params.merge(plan_id: target_plan.id),
        subscription:
      )
      override_result.fixed_charge
    end

    def update_fixed_charge_override(existing_fixed_charge)
      if params.key?(:properties)
        existing_fixed_charge.properties = ChargeModels::FilterPropertiesService.call(
          chargeable: existing_fixed_charge,
          properties: params[:properties].presence
        ).properties
      end
      existing_fixed_charge.invoice_display_name = params[:invoice_display_name] if params.key?(:invoice_display_name)
      existing_fixed_charge.units = params[:units] if params.key?(:units)
      existing_fixed_charge.save!

      FixedCharges::EmitEventsForActiveSubscriptionsService.call!(
        fixed_charge: existing_fixed_charge,
        subscription:,
        apply_units_immediately: !!params[:apply_units_immediately]
      )

      if params.key?(:tax_codes)
        taxes_result = FixedCharges::ApplyTaxesService.call(fixed_charge: existing_fixed_charge, tax_codes: params[:tax_codes])
        taxes_result.raise_if_error!
      end

      existing_fixed_charge.reload
    end
  end
end

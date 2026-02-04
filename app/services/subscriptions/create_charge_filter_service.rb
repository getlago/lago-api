# frozen_string_literal: true

module Subscriptions
  class CreateChargeFilterService < BaseService
    Result = BaseResult[:charge_filter]

    def initialize(subscription:, charge:, params:)
      @subscription = subscription
      @charge = charge
      @params = params

      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "subscription") unless subscription
      return result.not_found_failure!(resource: "charge") unless charge
      return result.single_validation_failure!(field: :values, error_code: "value_is_mandatory") if params[:values].blank?

      ActiveRecord::Base.transaction do
        target_plan = ensure_plan_override
        target_charge = find_or_create_charge_override(target_plan)

        create_result = ChargeFilters::CreateService.call!(
          charge: target_charge,
          params:
        )

        result.charge_filter = create_result.charge_filter
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :subscription, :charge, :params

    def ensure_plan_override
      current_plan = subscription.plan

      if current_plan.parent_id
        current_plan
      else
        override_result = Plans::OverrideService.call!(
          plan: current_plan,
          params: {},
          subscription:
        )
        subscription.update!(plan: override_result.plan)
        override_result.plan
      end
    end

    def find_or_create_charge_override(target_plan)
      parent_charge = find_parent_charge
      existing_override = target_plan.charges.find_by(parent_id: parent_charge.id)

      if existing_override
        existing_override
      else
        override_result = Charges::OverrideService.call!(
          charge: parent_charge,
          params: {plan_id: target_plan.id}
        )
        override_result.charge
      end
    end

    def find_parent_charge
      if charge.parent_id
        charge.parent
      else
        charge
      end
    end
  end
end

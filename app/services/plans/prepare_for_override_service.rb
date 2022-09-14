# frozen_string_literal: true

module Plans
  class PrepareForOverrideService
    def initialize(organization, plan_code)
      @organization = organization
      @plan_code = plan_code
    end

    def call(plan_params:)
      plan = plan_params.to_h

      (plan[:charges] || []).each do |input_charge|
        charge = Charge.find_by(id: input_charge[:id])
        input_charge[:billable_metric_id] = charge&.billable_metric_id
        input_charge.delete(:id)
      end

      return plan unless overridden_plan

      plan[:code] = "#{overridden_plan.code}-#{SecureRandom.uuid}"
      plan[:name] = overridden_plan.name
      plan[:description] = overridden_plan.description
      plan[:bill_charges_monthly] = overridden_plan.bill_charges_monthly
      plan[:interval] = overridden_plan.interval
      plan[:pay_in_advance] = overridden_plan.pay_in_advance
      plan[:overridden_plan_id] = overridden_plan.id
      plan[:organization_id] = organization.id

      plan
    end

    private

    attr_reader :organization, :plan_code

    def overridden_plan
      @overridden_plan ||= begin
        organization.plans.find_by(code: plan_code)
      end
    end
  end
end

# frozen_string_literal: true

module Plans
  class ValidateService
    def initialize(result, **args)
      @result = result
      @args = args
    end

    def valid?
      errors = []
      errors << 'overridden_plan_not_found' if invalid_overridden_plan?
      errors << 'incorrect_charge_number' if invalid_charge_number?
      errors = errors.compact

      unless errors.empty?
        result.fail!(
          code: 'unprocessable_entity',
          message: 'Validation error on the record',
          details: errors,
        )
        return false
      end

      true
    end

    private

    attr_accessor :result, :args

    def invalid_overridden_plan?
      return false unless args[:overridden_plan_id]

      overridden_plan.blank?
    end

    def invalid_charge_number?
      return false unless args[:overridden_plan_id]
      return args[:charges].present? unless overridden_plan
      return overridden_plan.charges.count.positive? if args[:charges].nil?

      args[:charges].count != overridden_plan.charges.count
    end

    def overridden_plan
      @overridden_plan ||= Plan.find_by(id: args[:overridden_plan_id], organization_id: args[:organization_id])
    end
  end
end

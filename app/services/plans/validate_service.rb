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

      Plan.find_by(id: args[:overridden_plan_id], organization_id: args[:organization_id]).blank?
    end
  end
end

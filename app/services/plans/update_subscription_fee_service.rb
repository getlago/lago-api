# frozen_string_literal: true

module Plans
  class UpdateSubscriptionFeeService < BaseService
    def initialize(plan:, amount_cents:)
      @plan = plan
      @amount_cents = amount_cents

      super
    end

    def call
      return result.not_found_failure!(resource: 'plan') unless plan

      plan.amount_cents = amount_cents
      plan.save!

      result.plan = plan
      result
    end

    private

    attr_reader :plan, :amount_cents
  end
end

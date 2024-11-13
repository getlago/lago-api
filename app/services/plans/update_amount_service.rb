# frozen_string_literal: true

module Plans
  class UpdateAmountService < BaseService
    def initialize(plan:, amount_cents:, expected_amount_cents:)
      @plan = plan
      @amount_cents = amount_cents
      @expected_amount_cents = expected_amount_cents

      super
    end

    def call
      return result.not_found_failure!(resource: 'plan') unless plan

      result.plan = plan
      return result if plan.amount_cents != expected_amount_cents

      plan.amount_cents = amount_cents
      plan.save!

      result
    end

    private

    attr_reader :plan, :amount_cents, :expected_amount_cents
  end
end

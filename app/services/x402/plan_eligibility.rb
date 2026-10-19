# frozen_string_literal: true

module X402
  module PlanEligibility
    CURRENCY = "USD"

    def self.refusal(plan)
      if plan.amount_currency != CURRENCY
        "plan_currency_not_supported"
      elsif !usage_only?(plan)
        "plan_not_usage_only"
      end
    end

    def self.usage_only?(plan)
      plan.amount_cents.zero? &&
        plan.minimum_commitment.nil? &&
        !plan.fixed_charges.exists? &&
        !plan.charges.where(min_amount_cents: 1..).exists?
    end
  end
end

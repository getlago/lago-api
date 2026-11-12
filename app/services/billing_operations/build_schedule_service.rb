# frozen_string_literal: true

module BillingOperations
  class BuildScheduleService < Billing::RateCards::BuildScheduleService
    private

    def build_schedule(**attributes)
      Schedule.new(**attributes, final_billing_at: contract_rate_card.contract.terminated_at)
    end
  end
end

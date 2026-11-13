# frozen_string_literal: true

module BillingOperations
  class BuildScheduleService < Billing::RateCards::BuildScheduleService
    private

    def build_schedule(**attributes)
      Schedule.new(**attributes)
    end
  end
end

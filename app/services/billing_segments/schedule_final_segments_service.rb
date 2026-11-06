# frozen_string_literal: true

module BillingSegments
  # Schedules what a contract's priced cards still owe up to its end, whatever their clock: a
  # termination writes the period still open itself, since the clock only bills active contracts.
  class ScheduleFinalSegmentsService < ScheduleService
    def initialize(contract:, timestamp:)
      @contract = contract
      super(customer: contract.customer, timestamp:)
    end

    private

    attr_reader :contract

    def cards_to_schedule
      ContractRateCard.priced.starting_before_contract_end
        .where(organization_id: contract.organization_id, contract_id: contract.id)
    end
  end
end

# frozen_string_literal: true

module Contracts
  # Testing helper: brings billing up to an instant and invoices whatever that produced.
  # The same two steps the clock takes, in the same order, without waiting for the tick.
  #
  # Billing is customer-grained, not contract-grained: the consumer groups a customer's
  # segments into as few invoices as their contracts allow. The contracts asked for select
  # the customers, so a customer's other contracts bill in the same run — exactly as they
  # would on the clock. Anything narrower would be a path production never takes.
  #
  # There is no start date. Each card resumes from its own clock, so the only question a
  # caller can answer is how far forward to go.
  class BillService < BaseService
    Result = BaseResult[:invoices]

    def initialize(contracts:, timestamp: Time.current)
      @contracts = contracts
      @timestamp = timestamp
      super
    end

    def call
      result.invoices = customers.flat_map do |customer|
        BillingSegments::ScheduleService.call!(customer:, timestamp:)
        BillingSegments::ProcessService.call!(customer:).invoices
      end

      result
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :contracts, :timestamp

    def customers
      Customer.where(id: contracts.map(&:customer_id).uniq)
    end
  end
end

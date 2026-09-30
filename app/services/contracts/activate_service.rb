# frozen_string_literal: true

module Contracts
  # Starts a pending contract once its start has arrived and schedules its
  # first billing. A pending contract with an active sibling on the same
  # external id is a replacement whose predecessor should have been ended by
  # the handover: activation fails rather than leave it waiting unnoticed.
  class ActivateService < BaseService
    Result = BaseResult[:contract]

    def initialize(contract:, timestamp: Time.current)
      @contract = contract
      @timestamp = timestamp
      super
    end

    def call
      return result.not_found_failure!(resource: "contract") unless contract

      ActiveRecord::Base.transaction do
        # Re-read under lock: a contract canceled since it was loaded stays canceled.
        contract.lock!
        next unless due?

        if active_sibling?
          return result.single_validation_failure!(field: :external_id, error_code: "active_contract_exists")
        end

        contract.update!(status: :active)
        BillingSegments::ScheduleJob.perform_after_commit(contract.customer_id)
      end

      result.contract = contract
      result
    end

    private

    attr_reader :contract, :timestamp

    def due?
      contract.pending? && contract.started_at.present? && contract.started_at <= timestamp
    end

    def active_sibling?
      Contract.active.exists?(organization_id: contract.organization_id, external_id: contract.external_id)
    end
  end
end

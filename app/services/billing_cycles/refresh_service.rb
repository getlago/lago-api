# frozen_string_literal: true

module BillingCycles
  # Seed the first period, or refresh it while the contract is still being authored.
  class RefreshService < BaseService
    Result = BaseResult[:billing_cycle]

    def initialize(contract_rate_card:)
      @contract_rate_card = contract_rate_card
      super
    end

    def call
      contract_rate_card.with_lock do
        if !contract_rate_card.contract.pending? && contract_rate_card.billing_cycles.exists?
          return result.single_validation_failure!(field: :contract, error_code: "contract_locked")
        end

        if contract_rate_card.rate_card.rates.empty?
          return result
        end

        contract_rate_card.rate_phases.reset
        schedule = Billing::RateCards::BuildScheduleService.call!(contract_rate_card:).schedule
        cycle = schedule.first_cycle

        if cycle
          record = contract_rate_card.billing_cycles.find_or_initialize_by(cycle_index: cycle.cycle_index)
          record.assign_attributes(
            organization_id: contract_rate_card.organization_id,
            started_at: cycle.started_at,
            ended_at: cycle.ended_at,
            timezone: cycle.timezone
          )
          if record.changed?
            record.save!
          end
          result.billing_cycle = record
        else
          contract_rate_card.billing_cycles.destroy_all
        end

        contract_rate_card.update!(next_billing_at: schedule.billing_at_covering(Time.current))
      end

      result
    rescue ActiveRecord::RecordInvalid => error
      result.record_validation_failure!(record: error.record)
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :contract_rate_card
  end
end

# frozen_string_literal: true

module BillingCycles
  class CreateService < BaseService
    Result = BaseResult[:billing_cycles]

    def initialize(contract_rate_card:, cycles:)
      @contract_rate_card = contract_rate_card
      @cycles = cycles
      super
    end

    def call
      result.billing_cycles = []
      rows = cycles.uniq(&:index).map { attributes_for(it) }

      if rows.empty?
        return result
      end

      BillingCycle.transaction(requires_new: true) do
        # Insert together so backfilling years of periods does not issue a query per cycle.
        # The calendar supplies the bounds; DB constraints enforce their ordering/identity.
        BillingCycle.insert_all(rows, unique_by: [:contract_rate_card_id, :cycle_index]) # rubocop:disable Rails/SkipsModelValidations
        persisted = contract_rate_card.billing_cycles.where(cycle_index: rows.pluck(:cycle_index)).index_by(&:cycle_index)

        # Another pricing slice can reuse the period, but must not rewrite its calendar.
        if rows.any? { |row| row.any? { |name, value| persisted.fetch(row[:cycle_index]).public_send(name) != value } }
          result.single_validation_failure!(field: :billing_cycle, error_code: "calendar_conflict").raise_if_error!
        end

        result.billing_cycles = rows.map { persisted.fetch(it[:cycle_index]) }
      end

      result
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :contract_rate_card, :cycles

    def attributes_for(cycle)
      reference = cycle.calendar.interval_containing(cycle.started_at)

      {
        organization_id: contract_rate_card.organization_id,
        contract_rate_card_id: contract_rate_card.id,
        cycle_index: cycle.index,
        started_at: cycle.started_at,
        ended_at: reference.end,
        reference_started_at: reference.begin,
        timezone: cycle.calendar.timezone
      }
    end
  end
end

# frozen_string_literal: true

module BillingCycles
  class CreateService < BaseService
    Result = BaseResult[:billing_cycle]

    def initialize(contract_rate_card:, cycle:)
      @contract_rate_card = contract_rate_card
      @cycle = cycle
      super
    end

    def call
      # Serialize creation per card, including retries that race for the same index.
      contract_rate_card.with_lock(requires_new: true) do
        billing_cycle = contract_rate_card.billing_cycles.find_or_initialize_by(cycle_index: cycle.index)
        attributes = calendar_attributes

        if billing_cycle.persisted? && attributes.any? { |name, value| billing_cycle.public_send(name) != value }
          result.single_validation_failure!(field: :billing_cycle, error_code: "calendar_conflict")
        else
          unless billing_cycle.persisted?
            billing_cycle.assign_attributes(attributes)
            billing_cycle.save!
          end

          result.billing_cycle = billing_cycle
        end
      end

      result
    rescue ActiveRecord::RecordInvalid => error
      result.record_validation_failure!(record: error.record)
    rescue ActiveRecord::RecordNotUnique
      result.single_validation_failure!(field: :billing_cycle, error_code: "calendar_conflict")
    end

    private

    attr_reader :contract_rate_card, :cycle

    def calendar_attributes
      # The walker clips its service window. Persist the containing calendar period
      # instead, retaining the denominator for initial stubs and early termination.
      period = cycle.calendar.interval_containing(cycle.started_at)

      {
        organization_id: contract_rate_card.organization_id,
        started_at: period.begin,
        ended_at: period.end,
        timezone: cycle.calendar.timezone
      }
    end
  end
end

# frozen_string_literal: true

module ContractRateCards
  class ChangeUnitsService < BaseService
    Result = BaseResult[:contract_rate_card]
    APPLICATION_TIMINGS = %w[now next_billing_period].freeze

    def initialize(contract_rate_card:, params:)
      @contract_rate_card = contract_rate_card
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      validate_request
      return result if result.failure?

      Customers::LockService.call!(customer: contract_rate_card.contract.customer, scope: :billing_schedule) do
        lock_contract_and_card
        validate_card
        apply_units_change if result.success?
      end

      result.contract_rate_card = contract_rate_card if result.success?
      result
    rescue ActiveRecord::RecordInvalid => error
      result.record_validation_failure!(record: error.record)
    rescue ActiveRecord::RecordNotUnique => error
      unique_index_failure!(error,
        "index_units_reconciliation_history" => :units,
        "index_current_contract_rate_card_terms" => :units)
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error.result.error)
    rescue BaseLockService::FailedToAcquireLock => error
      result.lock_acquisition_failure!(message: error.message, error:)
    end

    private

    attr_reader :contract_rate_card, :params, :timestamp

    def validate_request
      if !APPLICATION_TIMINGS.include?(params[:apply_units])
        result.single_validation_failure!(field: :apply_units, error_code: "value_is_invalid")
      elsif params.keys.any? { !it.in?(%w[units apply_units]) }
        result.single_validation_failure!(field: :contract, error_code: "contract_locked")
      elsif params[:units].nil?
        result.single_validation_failure!(field: :units, error_code: "value_is_mandatory")
      end
    end

    def lock_contract_and_card
      contract_rate_card.contract.lock!
      contract_rate_card.lock!
    end

    def validate_card
      if !contract_rate_card.contract.active?
        result.single_validation_failure!(field: :contract, error_code: "contract_locked")
      elsif !contract_rate_card.product.fixed?
        result.single_validation_failure!(field: :units, error_code: "value_is_invalid")
      end
    end

    def apply_units_change
      @timestamp = Time.current.floor(6)
      schedule = Billing::RateCards::BuildScheduleService.call!(contract_rate_card:).schedule
      cycle = schedule.cycle_at(timestamp)
      return result.single_validation_failure!(field: :contract, error_code: "contract_locked") unless cycle

      if params[:apply_units] == "now"
        record_units_change(schedule)
      else
        schedule_units_change(schedule)
      end
      return result if result.failure?

      contract_rate_card.touch # rubocop:disable Rails/SkipsModelValidations
      SendWebhookJob.perform_after_commit("contract_rate_card.updated", contract_rate_card)
    end

    def record_units_change(schedule)
      existing = contract_rate_card.units_changes.find_by(billing_at: timestamp)
      if existing
        code = existing.processed_at ? "units_already_billed" : "value_already_exist"
        return result.single_validation_failure!(field: :units, error_code: code)
      end

      segment = schedule.segment_covering(timestamp)
      return result.single_validation_failure!(field: :units, error_code: "no_effective_rate") unless segment

      units_before = UnitsAtService.call!(contract_rate_card:, timestamp:).units || 0.to_d
      planned_operation = BillingOperations::Schedule::BuildPlannedOperation::PlannedOperation.new(
        segment: segment.with(started_at: timestamp), billing_at: timestamp
      )
      creation = BillingOperations::CreateService.call(contract_rate_card:, action_type: "reconcile_advance_coverage",
        reason: "contract_units_change", planned_operation:, units_before:, units_after: params[:units])
      if creation.failure?
        error = creation.error
        error = error.remap(result) { |field| (field == :units_after) ? :units : field } if error.is_a?(BaseService::ValidationFailure)
        return result.fail_with_error!(error)
      end
      contract_rate_card.units_changes.reset
    end

    def schedule_units_change(schedule)
      effective_date = timestamp.in_time_zone(contract_rate_card.contract.customer.applicable_timezone).to_date
      return result.single_validation_failure!(field: :contract, error_code: "contract_locked") unless schedule.next_segment_start(after_date: effective_date)

      history = ContractRateCardUnitsHistoryQuery.call!(organization: contract_rate_card.organization,
        contract_rate_cards: [contract_rate_card]).histories.fetch(contract_rate_card.id)
      term = contract_rate_card.terms.build(organization: contract_rate_card.organization, units: params[:units],
        effective_date:, application_timing: :next_billing_cycle)
      term.save!
      history.pending_terms_at(timestamp).each(&:destroy!)
      contract_rate_card.terms.reset
    end
  end
end

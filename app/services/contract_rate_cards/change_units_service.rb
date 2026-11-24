# frozen_string_literal: true

module ContractRateCards
  class ChangeUnitsService < BaseService
    Result = BaseResult[:contract_rate_card]
    APPLICATION_TIMINGS = {"now" => "current_billing_cycle", "next_billing_period" => "next_billing_cycle"}.freeze

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
      unique_index_failure!(error, "index_contract_rate_card_terms_on_card_and_instant" => :effective_at)
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    rescue BaseLockService::FailedToAcquireLock => error
      result.lock_acquisition_failure!(message: error.message, error:)
    end

    private

    attr_reader :contract_rate_card, :params, :timestamp

    def validate_request
      if !APPLICATION_TIMINGS.key?(params[:apply_units])
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

      effective_at = (params[:apply_units] == "now") ? timestamp : cycle.ended_at
      term = contract_rate_card.terms.find_or_initialize_by(effective_at:)
      if term.persisted? && contract_rate_card.billing_operations.completed.where(billing_at: effective_at).exists?
        return result.single_validation_failure!(field: :units, error_code: "units_already_billed")
      end

      save_units_term(term)
      schedule_advance_adjustment(cycle:, effective_at:)
      SendWebhookJob.perform_after_commit("contract_rate_card.updated", contract_rate_card)
    end

    def save_units_term(term)
      term.assign_attributes(organization: contract_rate_card.organization, units: params[:units],
        application_timing: APPLICATION_TIMINGS.fetch(params[:apply_units]))
      term.save!
      contract_rate_card.touch # rubocop:disable Rails/SkipsModelValidations
    end

    def schedule_advance_adjustment(cycle:, effective_at:)
      return unless contract_rate_card.rate_card.advance? && effective_at == timestamp

      unless contract_rate_card.billing_operations.pending.exists?(action_type: "adjust_fixed_advance", billing_at: timestamp)
        create_advance_adjustment(cycle)
      end
      BillingOperations::ProcessJob.perform_after_commit(contract_rate_card.contract.customer_id)
    end

    def create_advance_adjustment(cycle)
      planned_operation = BillingOperations::Schedule::BuildPlannedOperation::PlannedOperation.new(
        cycle_started_at: cycle.started_at, billing_at: timestamp
      )
      BillingOperations::CreateService.call!(contract_rate_card:, action_type: "adjust_fixed_advance",
        reason: "contract_units_change", planned_operation:)
    end
  end
end

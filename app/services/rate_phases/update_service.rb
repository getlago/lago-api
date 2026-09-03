# frozen_string_literal: true

module RatePhases
  # Updates a single phase, addressed by its code. Positions are not editable
  # here: ordering changes go through insert/delete, which renumber safely.
  class UpdateService < BaseService
    Result = BaseResult[:rate_phase]

    def initialize(rate_phase:, params:)
      @rate_phase = rate_phase
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "rate_phase") unless rate_phase

      # REST can send "" where nil is meant; normalize before the terminal
      # check or the blank slips past it and persists as an indefinite phase.
      if params.key?(:billing_interval_cycle_count)
        params[:billing_interval_cycle_count] = params[:billing_interval_cycle_count].presence
      end

      parent.with_lock do
        if (locked = lock_error_code)
          return result.single_validation_failure!(field: :rate_phase, error_code: locked)
        end

        if params.key?(:billing_interval_cycle_count) && params[:billing_interval_cycle_count].nil? && !last_phase?
          return result.single_validation_failure!(field: :billing_interval_cycle_count, error_code: "indefinite_phase_must_be_last")
        end

        rate_phase.name = params[:name] if params.key?(:name)
        rate_phase.code = params[:code] if params.key?(:code)
        if params.key?(:billing_interval_cycle_count)
          rate_phase.billing_interval_cycle_count = params[:billing_interval_cycle_count]
        end

        superseded_override_id = nil
        if params.key?(:rate_override)
          superseded_override_id = rate_phase.rate_override_id
          rate_phase.rate_override = build_override
        end

        rate_phase.save!

        if superseded_override_id && superseded_override_id != rate_phase.rate_override_id
          RateOverride.find_by(id: superseded_override_id)&.discard!
        end
      end

      result.rate_phase = rate_phase
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :rate_phase, :params

    def parent
      rate_phase.plan_rate_card || rate_phase.contract_rate_card
    end

    # A provided rate_override replaces the phase's override; null clears it.
    def build_override
      return if params[:rate_override].nil?

      RateOverrides::CreateService.call(
        rate_card: parent.rate_card,
        params: params[:rate_override]
      ).raise_if_error!.rate_override
    end

    def lock_error_code
      case parent
      when PlanRateCard
        "plan_locked" if parent.plan.attached_to_subscriptions?
      when ContractRateCard
        "contract_locked" if parent.contract.locked?
      end
    end

    def last_phase?
      parent.rate_phases.order(:position).last == rate_phase
    end
  end
end

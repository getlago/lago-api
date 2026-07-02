# frozen_string_literal: true

module RatePhases
  class ReplaceService < BaseService
    Result = BaseResult[:rate_phases]

    def initialize(plan_product_item:, phases_params:)
      @plan_product_item = plan_product_item
      @phases_params = Array.wrap(phases_params).map { |phase| phase.to_h.with_indifferent_access }
      super
    end

    def call
      return result.not_found_failure!(resource: "plan_product_item") unless plan_product_item
      return result.single_validation_failure!(field: :rate_phases, error_code: "plan_locked") if plan_locked?

      sequence_failure = validate_sequence
      return sequence_failure if sequence_failure

      ActiveRecord::Base.transaction do
        plan_product_item.rate_phases.discard_all!

        result.rate_phases = ordered_params.map do |phase|
          plan_product_item.rate_phases.create!(
            organization:,
            position: phase[:position],
            name: phase[:name],
            billing_interval_cycle_count: phase[:billing_interval_cycle_count]
          )
        end
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :plan_product_item, :phases_params

    def organization
      plan_product_item.organization
    end

    def plan_locked?
      plan_product_item.plan.attached_to_subscriptions?
    end

    def ordered_params
      @ordered_params ||= phases_params.sort_by { |phase| phase[:position].to_i }
    end

    def validate_sequence
      if phases_params.empty?
        return result.single_validation_failure!(field: :rate_phases, error_code: "value_is_mandatory")
      end

      positions = ordered_params.map { |phase| phase[:position].to_i }
      unless positions == (1..phases_params.size).to_a
        return result.single_validation_failure!(field: :rate_phases, error_code: "non_contiguous_position")
      end

      # An indefinite tail (null billing_interval_cycle_count) is only allowed on the last phase.
      ordered_params[0...-1].each do |phase|
        if phase[:billing_interval_cycle_count].blank?
          return result.single_validation_failure!(field: :rate_phases, error_code: "non_terminal_indefinite")
        end
      end

      nil
    end
  end
end

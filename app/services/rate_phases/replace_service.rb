# frozen_string_literal: true

module RatePhases
  class ReplaceService < BaseService
    Result = BaseResult[:rate_phases]

    def initialize(plan_rate_card: nil, subscription_rate_card: nil, phases_params: [])
      @plan_rate_card = plan_rate_card
      @subscription_rate_card = subscription_rate_card
      @phases_params = Array.wrap(phases_params).map { |phase| phase.to_h.with_indifferent_access }
      super
    end

    def call
      return result.not_found_failure!(resource: "rate_phaseable") unless parent
      return result.single_validation_failure!(field: :rate_phases, error_code: "plan_locked") if plan_locked?
      return result.single_validation_failure!(field: :rate_phases, error_code: "subscription_locked") if subscription_locked?

      sequence_failure = validate_sequence
      return sequence_failure if sequence_failure

      ActiveRecord::Base.transaction do
        discard_existing_phases

        result.rate_phases = ordered_params.map do |phase|
          parent.rate_phases.create!(
            organization:,
            position: phase[:position],
            name: phase[:name],
            billing_interval_cycle_count: phase[:billing_interval_cycle_count],
            rate_override: build_override(phase)
          )
        end
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :plan_rate_card, :subscription_rate_card, :phases_params

    def parent
      plan_rate_card || subscription_rate_card
    end

    def organization
      parent.organization
    end

    def discard_existing_phases
      existing_phases = parent.rate_phases.to_a
      RateOverride.where(id: existing_phases.filter_map(&:rate_override_id)).discard_all!
      parent.rate_phases.discard_all!
    end

    def build_override(phase)
      return if phase[:rate_override].blank?

      RateOverrides::CreateService.call(
        rate_card: parent.rate_card,
        params: phase[:rate_override]
      ).raise_if_error!.rate_override
    end

    # Plan-level phases freeze once the plan has subscriptions; a
    # subscription's own phases are editable only while the subscription is
    # pending — once active, its pricing is signed.
    def plan_locked?
      plan_rate_card.present? && plan_rate_card.plan.attached_to_subscriptions?
    end

    def subscription_locked?
      subscription_rate_card.present? && !subscription_rate_card.subscription.pending?
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

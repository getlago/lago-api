# frozen_string_literal: true

module RatePhases
  # Removes a single phase. Later phases shift up; deleting an indefinite
  # terminal phase promotes the new last phase to indefinite, so the sequence
  # always keeps a coherent tail.
  class DestroyService < BaseService
    Result = BaseResult[:rate_phase]

    def initialize(rate_phase:)
      @rate_phase = rate_phase
      super
    end

    def call
      return result.not_found_failure!(resource: "rate_phase") unless rate_phase

      # Sequence reads and renumbering run under a parent lock: two concurrent
      # deletions computing from the same positions would leave gaps.
      parent.with_lock do
        if plan_locked?
          return result.single_validation_failure!(field: :rate_phase, error_code: "plan_locked")
        end

        if subscription_locked?
          return result.single_validation_failure!(field: :rate_phase, error_code: "subscription_locked")
        end

        siblings = parent.rate_phases.order(:position).to_a
        if siblings.size == 1
          return result.single_validation_failure!(field: :rate_phase, error_code: "cannot_delete_last_phase")
        end

        was_terminal_indefinite = siblings.last == rate_phase && rate_phase.billing_interval_cycle_count.nil?

        rate_phase.discard!
        rate_phase.rate_override&.discard!

        siblings.select { |phase| phase.position > rate_phase.position }.each do |phase|
          phase.update!(position: phase.position - 1)
        end

        if was_terminal_indefinite
          new_last = (siblings - [rate_phase]).last
          new_last.update!(billing_interval_cycle_count: nil)
        end
      end

      result.rate_phase = rate_phase
      result
    end

    private

    attr_reader :rate_phase

    def parent
      rate_phase.plan_rate_card || rate_phase.subscription_rate_card
    end

    def plan_locked?
      rate_phase.plan_rate_card.present? && rate_phase.plan_rate_card.plan.attached_to_subscriptions?
    end

    def subscription_locked?
      rate_phase.subscription_rate_card.present? && !rate_phase.subscription_rate_card.subscription.pending?
    end
  end
end

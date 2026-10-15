# frozen_string_literal: true

module RatePhases
  # Updates a single phase, addressed by its code. A new position moves the
  # phase within the sequence; the indefinite tail stays pinned last.
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

      applied_rate_card.with_lock do
        if (blocked = applied_rate_card.edit_error_code)
          return result.single_validation_failure!(field: :rate_phase, error_code: blocked)
        end

        # The phase was loaded before the lock; a concurrent move may have
        # renumbered it, and the shift below trusts its position. A concurrent
        # delete leaves it discarded: reload runs unscoped and does not raise.
        rate_phase.reload
        return result.not_found_failure!(resource: "rate_phase") if rate_phase.discarded?

        siblings = applied_rate_card.rate_phases.order(:position).to_a
        last = siblings.last == rate_phase

        # Duration checks come first: a tail swap through one update (moving a
        # phase last while making it indefinite) is not a thing, the tail is pinned.
        if params.key?(:billing_interval_cycle_count)
          if params[:billing_interval_cycle_count].nil? && !last
            return result.single_validation_failure!(field: :billing_interval_cycle_count, error_code: "indefinite_phase_must_be_last")
          end

          if params[:billing_interval_cycle_count].present? && last
            return result.single_validation_failure!(field: :billing_interval_cycle_count, error_code: "last_phase_must_be_indefinite")
          end
        end

        if params.key?(:position)
          target = RatePhase.parse_position(params[:position])
          failure = position_failure(target, siblings, last)
          return failure if failure

          move_to(target, siblings)
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

    def applied_rate_card
      rate_phase.plan_rate_card || rate_phase.contract_rate_card
    end

    # A provided rate_override replaces the phase's override; null clears it.
    def build_override
      return if params[:rate_override].nil?

      RateOverrides::CreateService.call(
        rate_card: applied_rate_card.rate_card,
        params: params[:rate_override]
      ).raise_if_error!.rate_override
    end

    def position_failure(target, siblings, last)
      if target.nil? || !target.between?(1, siblings.size)
        return result.single_validation_failure!(field: :position, error_code: "positions_must_be_contiguous")
      end

      if last && target != siblings.size
        return result.single_validation_failure!(field: :position, error_code: "indefinite_phase_must_be_last")
      end

      if !last && target == siblings.size
        return result.single_validation_failure!(field: :position, error_code: "last_phase_must_be_indefinite")
      end

      nil
    end

    # The phase parks on the free slot past the end while the others shift, so
    # the unique (card, position) index never sees two phases on one slot.
    def move_to(target, siblings)
      current = rate_phase.position
      return if target == current

      rate_phase.update!(position: siblings.map(&:position).max + 1)

      if target < current
        siblings.select { |phase| phase.position.between?(target, current - 1) }
          .sort_by(&:position).reverse_each { |phase| phase.update!(position: phase.position + 1) }
      else
        siblings.select { |phase| phase.position.between?(current + 1, target) }
          .sort_by(&:position).each { |phase| phase.update!(position: phase.position - 1) }
      end

      rate_phase.position = target
    end
  end
end

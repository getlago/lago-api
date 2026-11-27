# frozen_string_literal: true

module BillingOperations
  # Snapshots a target cycle's full schedule; consumers compare it with saved renewals.
  #
  # Example: the June 1 renewal saved A [Jun 1, Jul 1). A new price B starts Jun 15.
  #
  # Cycle scope: the schedule returns one obligation with two segments:
  #   [ A: Jun 1 -> Jun 15 | B: Jun 15 -> Jul 1 )
  #
  # Segment scope: the schedule returns two obligations for the same June 1 cycle:
  #   [ A: Jun 1 -> Jun 15 )  [ B: Jun 15 -> Jul 1 )
  #
  # Both produce one reconciliation containing both segments, retaining the first
  # obligation's cycle, terms and billing date. The original renewal stays unchanged;
  # consumers compare its saved A segment with the reconciliation's A and B segments.
  class BuildReconciliationObligationService < BaseService
    Result = BaseResult[:obligation]

    def initialize(schedule:, target_cycle_started_at:)
      @schedule = schedule
      @target_cycle_started_at = target_cycle_started_at
      super
    end

    def call
      obligations = schedule.obligations_for_cycle(target_cycle_started_at)
      return result if obligations.empty?

      result.obligation = obligations.first.with(segments: obligations.flat_map(&:segments))
      result
    end

    private

    attr_reader :schedule, :target_cycle_started_at
  end
end

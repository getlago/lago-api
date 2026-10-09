# frozen_string_literal: true

module BillingSegments
  # Of what a card owes by a given instant, which pieces are not stored yet. What comes in is
  # the calendar's answer, and it can include pieces an earlier run already wrote.
  #
  #   already stored     in, from the calendar         out
  #   (nothing)          Jan 1-Feb 1, Feb 1-Feb 15     both
  #   Feb 1-Feb 15       Feb 1-Feb 15, Feb 15-Mar 1    Feb 15-Mar 1
  #   Feb 1-Mar 1        Feb 1-Feb 15, Feb 15-Mar 1    (nothing)
  class MissingBillableSegmentsService < BaseService
    Result = BaseResult[:billable_segments]

    def initialize(contract_rate_card:, schedule:, timestamp:)
      @contract_rate_card = contract_rate_card
      @schedule = schedule
      @timestamp = timestamp
      super
    end

    def call
      due = schedule.segments_due_by(timestamp)

      if due.empty?
        result.billable_segments = []
        return result
      end

      settled = settled_periods(due)

      # Overlap, not an equal start: row 3 above is what an equal-start test gets wrong.
      result.billable_segments = due.reject do |billable_segment|
        period = billable_segment.started_at...billable_segment.ended_at

        settled.any? { |settled_period| settled_period.overlaps?(period) }
      end
      result
    end

    private

    attr_reader :contract_rate_card, :schedule, :timestamp

    # The second read of billing_segments — the first is the schedule's resume_at, a scalar that
    # cannot express a hole. The query it costs buys a walk bounded by the last stored cycle
    # rather than by the card's age, which matters for a daily card.
    #
    # Only the stored periods that could touch the candidates.
    #
    #   due    [Feb 1 -> Feb 15), [Feb 15 -> Mar 1)   what the calendar says is owed
    #   window Feb 1 -> Mar 1                         their union
    #   out    [Feb 1 .. Feb 14 23:59:59.999]         the half a previous run already billed
    def settled_periods(due)
      window = due.map(&:started_at).min...due.map(&:ended_at).max

      contract_rate_card.billing_segments
        .where(started_at: ...window.end, ended_at: window.begin..)
        .pluck(:started_at, :ended_at)
        .map { |started_at, ended_at| started_at..ended_at }
    end
  end
end

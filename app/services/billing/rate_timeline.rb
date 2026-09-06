# frozen_string_literal: true

module Billing
  # The rates of one rate card as a timeline: sorted once on construction, then asked many
  # times during the walk.
  #
  # It reads exactly one thing off a rate, `effective_from`, so anything that answers that
  # message can be put on a timeline.
  class RateTimeline
    delegate :empty?, to: :rates

    def initialize(rates)
      @rates = sort_by_effective_from(rates).freeze
    end

    # The rate in force at `timestamp`: the latest one effective at or before it, or nil
    # when `timestamp` precedes every rate.
    def at(timestamp)
      rates.rfind { |rate| rate.effective_from <= timestamp }
    end

    def earliest
      rates.first
    end

    # `window` cut at every rate change strictly inside it, so that each piece is priced by
    # a single rate.
    #
    #   window [Jun 1, Jul 1), rate B effective Jun 16
    #     => [Jun 1, Jun 16) priced A, [Jun 16, Jul 1) priced B
    #
    # RULE: a change landing exactly on either edge of the window is not a cut. It would
    # only produce an empty segment, and the rate it introduces already prices the window
    # on the other side of that edge.
    #
    # A leading piece with no rate in force yet is dropped rather than returned carrying a
    # nil rate: there is nothing to bill for it.
    def segments_within(window)
      boundaries = [window.begin, *cuts_inside(window), window.end]

      boundaries.each_cons(2).filter_map do |started_at, ended_at|
        rate_in_force = at(started_at)
        Segment.new(started_at:, ended_at:, rate: rate_in_force) if rate_in_force
      end
    end

    private

    attr_reader :rates

    # sort_by is not stable, so ties are broken by the order the rates were given in. Two
    # rates sharing an effective_from then always resolve the same way instead of flipping
    # between calls, and `at` consistently returns the last of them.
    def sort_by_effective_from(rates)
      rates.each_with_index.sort_by { |rate, index| [rate.effective_from, index] }.map(&:first)
    end

    # The rates are already sorted, so the cuts come out sorted; duplicates collapse to a
    # single cut, which is what keeps a repeated effective_from from opening an empty
    # segment.
    def cuts_inside(window)
      rates.map(&:effective_from).uniq.select { |effective_from| effective_from > window.begin && effective_from < window.end }
    end
  end
end

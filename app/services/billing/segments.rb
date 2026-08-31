# frozen_string_literal: true

module Billing
  # A cycle is billed as one fee unless a rate changes inside it. Each change part-way
  # through opens a segment: a separate fee over a sub-window at its own price, without
  # opening a new cycle — the segments of one cycle share its index.
  module Segments
    Segment = Data.define(:from, :to, :rate)

    # The windows `period` is billed as, in order. Rates are anything answering
    # `effective_from`; order does not matter.
    #
    # A change landing exactly on the period's start is simply the rate in force, so it
    # opens no segment. One landing on the end belongs to the next period, for the same
    # reason a boundary belongs to the period it opens.
    #
    # Where no rate is in force yet the window is dropped rather than billed at nothing:
    # billing starts at the first effective date and runs to the end of the period.
    #
    # @example [Sep 10, Oct 10) with a rate effective Sep 25
    #   [Sep 10, Sep 25) at the old rate, [Sep 25, Oct 10) at the new one
    def self.within(period, rates:)
      starts = [period.begin] + changes_inside(period, rates)

      starts.each_with_index.filter_map do |from, index|
        rate = rate_at(rates, from)
        next unless rate

        Segment.new(from:, to: starts[index + 1] || period.end, rate:)
      end
    end

    def self.changes_inside(period, rates)
      rates.map(&:effective_from)
        .select { |at| at > period.begin && period.cover?(at) }
        .uniq
        .sort
    end

    def self.rate_at(rates, instant)
      rates.select { |rate| rate.effective_from <= instant }.max_by(&:effective_from)
    end

    private_class_method :changes_inside, :rate_at
  end
end

# frozen_string_literal: true

module BillingPeriods
  # The catalog rates of one rate card, seen as a timeline.
  #
  # Rates are append-only and each takes effect from a moment, so at any instant exactly one
  # of them is in force: the last to have started. Answering that question is all this does —
  # which price applies, which billing interval it dictates, and where inside a window the
  # price changes hands.
  class RateTimeline
    def initialize(rates)
      @rates = rates.sort_by(&:effective_from)
    end

    delegate :empty?, to: :rates

    # The rate in force at a moment: the last one to have taken effect on or before it. The
    # newest never expires. Nil before the first one starts.
    def at(datetime)
      index = index_after(datetime)
      return if index.zero?

      rates[index - 1]
    end

    # The spacing a period opening here is laid out with, as [count, unit]. Normally the
    # interval of the rate in force; before the first rate starts there is none, so it falls
    # FORWARD to the first that does — the calendar needs a spacing either way. Nil only when
    # the card has no rates at all.
    def interval_at(datetime)
      rate = at(datetime) || rates[index_after(datetime)]
      return unless rate

      [rate.billing_interval_count, rate.billing_interval_unit]
    end

    # Where the price changes hands inside a window — the moments a period has to be cut at.
    # Almost always empty; rates rarely take effect mid-period.
    def changes_within(from, to)
      rates
        .select { |rate| rate.effective_from > from && rate.effective_from <= to }
        .map(&:effective_from)
    end

    # The [count, unit] every rate lays out on, or nil when they do not all agree. It is not a
    # yes/no on purpose: FixedInterval needs to know BOTH that the calendar is uniform and what
    # spacing to build its ruler with.
    #
    #   monthly, monthly     [1, "month"] [1, "month"]  ->  [1, "month"]
    #   monthly, weekly      [1, "month"] [1, "week"]   ->  nil
    #   monthly, quarterly   [1, "month"] [3, "month"]  ->  nil, the count counts as much as the unit
    def uniform_interval
      return @uniform_interval if defined?(@uniform_interval)

      intervals = rates.map { |rate| [rate.billing_interval_count, rate.billing_interval_unit] }

      @uniform_interval = intervals.uniq.one? ? intervals.first : nil
    end

    private

    attr_reader :rates

    def index_after(datetime)
      rates.bsearch_index { |rate| rate.effective_from > datetime } || rates.size
    end
  end
end

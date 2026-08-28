# frozen_string_literal: true

module BillingPeriods
  # The rates of one rate card, and which of them applies at a given moment — along with what
  # that rate says about how long its periods run and what it charges.
  #
  # Rates are append-only — each states the moment it takes effect and none states an end — so
  # the one in force is simply the last to have started, and the newest never expires. That is
  # what lets a rate dated in the future take over on its own, with nobody having to activate it.
  #
  # A rate phase can override what applies, and it overrides the price and the spacing in
  # DIFFERENT shapes. The schema is what makes them differ: `rate_model` and `rate_properties`
  # are NOT NULL on a rate_override, which is the same shape as a rate, so an override always
  # carries a complete price and replaces it wholesale. `billing_interval_count` and
  # `billing_interval_unit` are nullable, and each means "leave this half alone" — so an
  # override can say "weekly" while keeping the rate's count. Both rules live here so the
  # difference between them is visible rather than being a surprise in two distant files.
  class ApplicableRates
    def initialize(rates)
      @rates = rates.sort_by(&:effective_from)
    end

    # The rate in force at a moment: the last one to have taken effect on or before it. Nil
    # before the first one starts, which is possible — a card can begin before its catalog does.
    def at(moment)
      rates.rfind { |rate| rate.effective_from <= moment }
    end

    # How long a period opening at this moment runs for, as [count, unit].
    #
    # Before the first rate takes effect there is nothing in force, and the calendar still needs
    # a spacing to lay the first period out on, so this falls FORWARD to the first rate there
    # is. Those early periods get drawn and then dropped once they turn out to have no rate to
    # charge; without the fallback the calendar would have nowhere to start.
    #
    # Nil only when the card has no rates at all.
    def interval_at(moment, override = nil)
      rate = at(moment) || rates.first
      return unless rate

      [override&.billing_interval_count || rate.billing_interval_count,
        override&.billing_interval_unit || rate.billing_interval_unit]
    end

    # What a period opening at this moment is priced by. An override replaces it entirely, so
    # there is nothing to merge — unlike the interval above.
    def properties_at(moment, override = nil)
      (override || at(moment))&.properties
    end

    # Where the price changes hands inside a window — the moments a period has to be cut at.
    # Almost always empty; rates rarely take effect mid-period.
    #
    # Strictly after the window opens, because a rate taking effect at the opening does not cut
    # anything: it IS the window's rate. That is also what keeps a rate landing on a period
    # BOUNDARY from cutting the period before it — the boundary is the next midnight, the window
    # closes at 23:59:59.999 the day before, so it falls outside and governs the next period.
    def changes_within(from, to)
      rates.filter_map { |rate| rate.effective_from if rate.effective_from > from && rate.effective_from <= to }
    end

    private

    attr_reader :rates
  end
end

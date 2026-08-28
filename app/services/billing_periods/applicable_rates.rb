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
  #
  # Every example below is on the same card, and the two overrides come from a rate phase:
  #
  #   rates      Mar 1  ->  1 month,  {"amount" => "10"}
  #              Jun 1  ->  2 weeks,  {"amount" => "25"}
  #   weekly     an override setting only the unit    ("week", count nil, amount 10)
  #   discount   an override setting only the price   (count and unit both nil, amount 4)
  class ApplicableRates
    def initialize(rates)
      @rates = rates.sort_by(&:effective_from)
    end

    # The rate in force at a moment: the last one to have taken effect on or before it.
    #
    #   at(Jan 15)   => nil        a card can begin before its catalog does
    #   at(Apr 10)   => Mar's rate
    #   at(Jun 1)    => Jun's rate inclusive — it governs from the instant it states
    #   at(2030)     => Jun's rate the newest never expires
    def at(moment)
      rates.rfind { |rate| rate.effective_from <= moment }
    end

    # How long a period opening at this moment runs for, as [count, unit] — meant to be taken
    # apart on the way in, `count, unit = interval_at(...)`, so the names land where they are
    # used. Nil only when the card has no rates.
    #
    #   interval_at(Apr 10)                     => [1, "month"]  the rate's own
    #   interval_at(Apr 10, override: weekly)   => [1, "week"]   unit from the phase, count from the rate
    #   interval_at(Apr 10, override: discount) => [1, "month"]  a price-only phase reshapes nothing
    #   interval_at(Jan 15)                     => [1, "month"]  falls forward, see #spacing_rate
    #
    # Both halves count when comparing two of them: monthly and quarterly share a unit and are
    # different calendars, which is how the spacing changing partway through gets noticed.
    def interval_at(moment, override: nil)
      rate = spacing_rate(moment)
      return unless rate

      count = override&.billing_interval_count || rate.billing_interval_count
      unit = override&.billing_interval_unit || rate.billing_interval_unit

      [count, unit]
    end

    # What a period opening at this moment is priced by. An override carries a complete price,
    # so it replaces rather than merges — the opposite of the interval above.
    #
    #   properties_at(Apr 10)                     => {"amount" => "10"}
    #   properties_at(Apr 10, override: discount) => {"amount" => "4"}  replaced wholesale
    #   properties_at(Jan 15)                     => nil                nothing to charge
    #
    # Compare the middle line with the interval above it: the SAME override replaced the price
    # and left the spacing alone.
    def properties_at(moment, override: nil)
      (override || at(moment))&.properties
    end

    # Where the price changes hands inside a window — the moments a period has to be cut at.
    # Almost always empty; rates rarely take effect mid-period.
    #
    # Strictly after the window opens, and that one bound gives the last two lines below.
    #
    #   changes_within(Apr 1,  Apr 30)               => []       a quiet month
    #   changes_within(May 20, Jun 10)               => [Jun 1]  lands inside the window
    #   changes_within(May 1,  May 31 23:59:59.999)  => []       a change on the 1st never splits
    #                                                            the month before it
    #   changes_within(Jun 1,  Jun 30)               => []       it IS the window's own rate
    def changes_within(from, to)
      rates.filter_map { |rate| rate.effective_from if rate.effective_from > from && rate.effective_from <= to }
    end

    private

    attr_reader :rates

    # Which rate dictates the spacing here. Normally the one in force — but a card can begin
    # before its catalog does, and the calendar still needs a spacing to lay its first period
    # out on, so the earliest rate stands in. Those early periods are drawn and then dropped
    # once they turn out to have no rate to charge; without the stand-in there would be nowhere
    # to start at all.
    def spacing_rate(moment)
      at(moment) || rates.first
    end
  end
end

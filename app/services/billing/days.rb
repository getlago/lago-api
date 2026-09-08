# frozen_string_literal: true

module Billing
  module Days
    # Whole billable days in the half-open window [from, to).
    # A day belongs to the window holding its LOCAL midnight
    #
    # @example in "Europe/Paris"
    #   between(Jun  1 00:00, Jun  1 09:30)  # =>  1   a day begun counts whole
    #   between(Jun 16 09:30, Jul  1 00:00)  # => 14   the two sides sum to 30
    #   between(Mar  1 00:00, Apr  1 00:00)  # => 31   Mar 29 2026 loses an hour to DST (23h),
    #                                        #          but days are counted midnight-to-midnight,
    #                                        #          so the short day still counts as one
    def self.between(from, to, timezone:)
      (opening_date(to, timezone:) - opening_date(from, timezone:)).to_i
    end

    # The first local date whose midnight is at or after `timestamp`.
    #
    # @return [Date] tomorrow when part-way through a day — the day in progress was already
    #   given to whatever window opened it, so the next one to hand out is the next
    #
    # @example in "Europe/Paris"
    #   opening_date(Jun 16 00:00:00 Paris)  # => Jun 16   already a local midnight
    #   opening_date(Jun 16 00:00:01 Paris)  # => Jun 17   one second in, the day is spoken for
    #   opening_date(Jun 16 09:30    Paris)  # => Jun 17
    #   opening_date(Jun 16 00:00    UTC)    # => Jun 17   02:00 in Paris, so the 16th is gone
    #
    # Compares against midnight rather than adding a day, so a DST transition cannot shift it.
    def self.opening_date(timestamp, timezone:)
      local = timestamp.in_time_zone(timezone)

      (local == local.beginning_of_day) ? local.to_date : local.to_date + 1
    end
    private_class_method :opening_date
  end
end

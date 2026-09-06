# frozen_string_literal: true

module Billing
  # How far billing runs when a card is terminated.
  #
  # A day entered is a day paid for: terminating at any point inside a day bills that whole
  # day, whether a minute of it was served or all of it. So billing runs to the end of the
  # termination day where the CUSTOMER is, not to the termination instant.
  #
  #   terminated 2026-09-25 00:00 local  ->  billed through 2026-09-26 00:00
  #   terminated 2026-09-25 23:59 local  ->  the same
  #   terminated 2026-09-26 00:00 local  ->  2026-09-27 00:00
  #
  # Unconditional by design. Entering the day is what counts, so midnight is not a special
  # case and the time of day never changes the amount — which is the property to reach for
  # when this looks wrong: if 23:59 and 00:00 of the same day bill differently, the rule is
  # being applied somewhere other than here.
  #
  # This does NOT move `terminated_at`. The subscription ended when the customer said it
  # ended, and that instant is reported as given. This is only how far its last period is
  # billed, and the two are different facts.
  module TerminationDay
    # The exclusive end of the termination day: the next local midnight. Built from the local
    # date rather than by adding 24 hours, so a DST transition cannot shift it.
    def self.billed_through(terminated_at, timezone:)
      (terminated_at.in_time_zone(timezone).to_date + 1).in_time_zone(timezone)
    end
  end
end

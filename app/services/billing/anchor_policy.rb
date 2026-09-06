# frozen_string_literal: true

module Billing
  # What happens to the billing anchor when the cadence changes mid-schedule.
  #
  # One mode ships: LAGO-1766 ([QA] 23, QA approved 2026-08-14) chose "Reading B, where
  # everything is glued" and ruled explicitly against a second one — "we **won't add** a
  # `billing_anchor_mode` as a v1 so we keep thing simple and focus on other important
  # topic". A `Fixed` counterpart was written on 2026-09-04 and removed on 2026-09-06 once
  # that ticket was found: nothing in Linear, Notion or any staging run ever asked for it,
  # and no call site passed it.
  #
  # The SEAM is kept on purpose. `anchor_policy:` remains a parameter of Schedule and of
  # BuildScheduleService, so the day a second mode is genuinely wanted it is one module with
  # one method and no change to the walk:
  #
  #   module Fixed
  #     def self.anchor_after_cadence_change(previous_anchor, _cursor_date) = previous_anchor
  #   end
  #
  # What must NOT come back with it is a Boolean. The walk asks the same question of every
  # policy and takes the date it is handed; the moment it branches on which policy it holds,
  # a second mode costs a conditional in the one method where everything already meets.
  #
  # The question is asked at exactly one moment — a cycle whose interval differs from the
  # previous one — which is what the method is named for. Every other cycle carries the
  # anchor it already had.
  module AnchorPolicy
    # The anchor moves to the day the cadence changed, so the new cadence is measured from
    # the change: a weekly cycle taking over from a monthly one runs a whole week from the
    # day it took effect, rather than to whatever weekday the original anchor fell on.
    #
    #   monthly anchored Jan 1, two weekly cycles ending Feb 15, then monthly again
    #     => the next monthly cycle runs Feb 15 to Mar 15, and continues on the 15th
    module Realigning
      def self.anchor_after_cadence_change(_previous_anchor, cursor_date)
        cursor_date
      end
    end
  end
end

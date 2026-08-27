# frozen_string_literal: true

module BillingPeriods
  module Timing
    CLAIM_RULES = %i[billing_date overlap].freeze

    def self.for(rate_card:, range:, timezone:, terminated_at: nil, claim_by: :billing_date)
      return Termination.new(range:, timezone:, terminated_at:) if terminated_at

      case rate_card.billing_timing.to_sym
      when :advance then Advance.new(range:, timezone:, claim_by:)
      when :arrears then Arrears.new(range:, timezone:, claim_by:)
      else raise ArgumentError, "Invalid billing timing: #{rate_card.billing_timing}"
      end
    end

    class Base
      def initialize(range:, timezone:, claim_by: :billing_date)
        raise ArgumentError, "Invalid claim rule: #{claim_by}" unless CLAIM_RULES.include?(claim_by)

        @range = range
        @timezone = timezone
        @claim_by = claim_by
      end

      def window_for(period)
        [period.starts_at, period.ends_at]
      end

      def billed_at(_period)
        raise NotImplementedError
      end

      def next_billing_at_for(_boundaries, _position)
        raise NotImplementedError
      end

      def next_period_start_for(period)
        day_after(period)
      end

      def due?(period)
        return overlaps_range?(period) if claiming_by_overlap?

        billed_at(period).between?(range_begin, range_end)
      end

      def past_range?(period)
        return period.starts_at > range_end if claiming_by_overlap?

        billed_at(period) > range_end
      end

      private

      attr_reader :range, :timezone, :claim_by

      delegate :begin, :end, to: :range, prefix: true

      def claiming_by_overlap?
        claim_by == :overlap
      end

      def overlaps_range?(period)
        period.ends_at >= range_begin && period.starts_at <= range_end
      end

      def day_after(period)
        period.ends_at.in_time_zone(timezone).to_date.next_day.in_time_zone(timezone).utc
      end
    end

    class Advance < Base
      # It is billed the moment it opens.
      def billed_at(period)
        period.starts_at
      end

      # The next boundary: the period opening now closes when the next one opens.
      def next_billing_at_for(boundaries, position)
        boundaries.at(position + 1).utc
      end
    end

    # Billed once closed: the customer pays for a period that has already been served.
    #
    #   anchor Feb 1, monthly, run on Mar 1
    #   => period [Feb 1, Feb 28], billed Mar 1, next billing Apr 1
    class Arrears < Base
      # The day after it closes — a period served through May 31 is billed on Jun 1.
      def billed_at(period)
        day_after(period)
      end

      # Two boundaries out: this period is billed when the NEXT one closes, so the clock has
      # to point past it.
      def next_billing_at_for(boundaries, position)
        boundaries.at(position + 2).utc
      end
    end

    # Not a billing timing at all: everything overlapping the range, whatever the card's
    # timing says, with the last period cut at the termination instant.
    #
    # A cancellation may leave several unbilled periods behind it, and the caller decides
    # which become final fees, which become credits, and which become both. So it claims by
    # overlap — nothing about billing timing enters into it.
    class Termination < Base
      def initialize(range:, timezone:, terminated_at:)
        @terminated_at = terminated_at
        super(range:, timezone:, claim_by: :overlap)
      end

      # Cut at the cancellation rather than the period's natural end: service stops there, so
      # that is what the final cycle covers. This is the instant, not the day the run covers —
      # a card cancelled at 14:30 is billed through 14:30.
      def window_for(period)
        [period.starts_at, [period.ends_at, terminated_at].min]
      end

      # Every period it leaves behind falls due at the cancellation, whenever they would
      # otherwise have been billed. This is what a schedule-derived date cannot express.
      def billed_at(_period)
        terminated_at
      end

      def next_billing_at_for(boundaries, position)
        boundaries.at(position + 1).utc
      end

      private

      attr_reader :terminated_at
    end
  end
end

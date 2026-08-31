# frozen_string_literal: true

module BillingSegments
  # Schedules the charge owed when a pay-in-advance quantity rises part-way through a segment
  # that has already been invoiced. Returns nothing at all in every other case:
  #
  #   arrears                      the period-end segment already absorbs the change
  #   nothing billed yet           the ordinary producer will bill the whole segment
  #   a decrease                   never refunds, and never lowers the watermark
  #   a rise below the watermark   that coverage is already paid for
  #
  # The clock is deliberately left alone. Making the new version due would have the date
  # service regenerate the WHOLE period and bill it a second time — the successor inherits
  # next_billing_at precisely so that cannot happen. This service creates the one segment that
  # is genuinely owed instead.
  #
  # The window is [change, segment end] and the ratio is the share of the period still ahead
  # of the change, so the ordinary pricing path handles it as the partial period it is.
  class ScheduleAdvanceIncrementService < BaseService
    Result = BaseResult[:billing_segment]

    def initialize(subscription_rate_card:, at: Time.current)
      @subscription_rate_card = subscription_rate_card
      @at = at
      super
    end

    def call
      return result unless subscription_rate_card.rate_card.advance?
      return result unless base_segment
      return result unless rises_above_watermark?

      candidate.save!
      result.billing_segment = candidate
      result
    end

    private

    attr_reader :subscription_rate_card, :at

    def rises_above_watermark?
      units > ResolveWatermarkService.call!(billing_segment: candidate).units
    end

    def units
      @units ||= BigDecimal((subscription_rate_card.units || 0).to_s)
    end

    # Built unsaved so the watermark can be resolved against it before deciding to bill.
    def candidate
      @candidate ||= BillingSegment.new(
        organization: subscription_rate_card.organization,
        subscription: subscription_rate_card.subscription,
        customer: subscription_rate_card.customer,
        subscription_rate_card:,
        rate_card_rate: base_segment.rate_card_rate,
        rate_override: base_segment.rate_override,
        pricing_unit: base_segment.pricing_unit,
        rate_properties: base_segment.rate_properties,
        proration_ratio: remaining_ratio,
        period_from: at,
        period_to: base_segment.period_to,
        billing_at: at
      )
    end

    # The segment covering the change: its first segment, whose proration_ratio is the segment's
    # own share of the period. A rate change splits a period into segments invoiced separately,
    # so an increase belongs to the one it lands in.
    def base_segment
      return @base_segment if defined?(@base_segment)

      @base_segment = BillingSegment
        .where(subscription_rate_card_id: card_version_ids)
        .where(period_from: ..at)
        .where(period_to: at..)
        .where.not(status: :failed)
        .order(:period_from)
        .first
    end

    def card_version_ids
      subscription_rate_card.card_versions.select(:id)
    end

    # The segment's share of the period, narrowed to the days still ahead of the change.
    #
    #   whole period, change on day 2   1 x 30/31       = 30/31
    #   segment [1-14], change on day 3 14/31 x 12/14   = 12/31
    def remaining_ratio
      return BigDecimal(0) if segment_days.zero?

      base_segment.proration_ratio * remaining_days / segment_days
    end

    def segment_days
      @segment_days ||= days_between(base_segment.period_from, exclusive_end)
    end

    def remaining_days
      @remaining_days ||= days_between(at, exclusive_end)
    end

    def exclusive_end
      @exclusive_end ||= base_segment.period_to + 1.second
    end

    # Whole calendar days in the customer timezone, the same measure the units resolution and
    # the legacy engine use.
    def days_between(start_at, end_at)
      return 0 if end_at <= start_at

      (end_at.in_time_zone(timezone).to_date - start_at.in_time_zone(timezone).to_date).to_i
    end

    def timezone
      @timezone ||= subscription_rate_card.customer.applicable_timezone
    end
  end
end

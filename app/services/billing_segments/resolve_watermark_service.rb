# frozen_string_literal: true

module BillingSegments
  # The highest quantity already billed for the segment this segment belongs to — the watermark
  # a pay-in-advance increase is measured against.
  #
  # It is derived rather than stored. A units change versions the rate card, and an increase
  # that is billed gets a segment pointing at its version, so the versions carrying a segment are
  # exactly the quantities that have been paid for. Decreases never get a segment, which is why
  # the watermark cannot fall: a lower version simply never enters the maximum.
  #
  #   versions   v1(1)  v2(3)  v3(5)  v4(1)  v5(2)
  #   segments      yes    yes    yes     no     no
  #   watermark  max(1, 3, 5) = 5
  #
  # Scoped to the segment, not the calendar period. A rate change splits a period into
  # segments that are invoiced separately, each up front at its own price, so a segment is not
  # incremental to the one before it. Segments of one segment share a period_to: the original
  # covers [start, end] and each increase covers [change, end].
  #
  # Pending and processing segments count. They have not produced a fee yet, but they will, and
  # treating them as unpaid would bill the same units twice.
  class ResolveWatermarkService < BaseService
    Result = BaseResult[:units]

    def initialize(billing_segment:)
      @billing_segment = billing_segment
      super
    end

    def call
      result.units = SubscriptionRateCard
        .where(id: billed_segments.select(:subscription_rate_card_id))
        .maximum(:units) || BigDecimal(0)

      result
    end

    private

    attr_reader :billing_segment

    # Only what came BEFORE this segment. Pricing is not a one-shot: a segment is priced when it
    # is processed, and re-priced on a retry or a preview, by which time later increases may
    # already exist. Counting those would make an earlier increase look like it sits under a
    # watermark that had not been reached yet, and bill it as zero.
    #
    # Increases are ordered by the moment they took effect, which is exactly period_from.
    def billed_segments
      BillingSegment
        .where(subscription_rate_card_id: card_version_ids)
        .where(period_to: billing_segment.period_to)
        .where(period_from: ...billing_segment.period_from)
        .where.not(status: :failed)
    end

    def card_version_ids
      billing_segment.subscription_rate_card.card_versions.select(:id)
    end
  end
end

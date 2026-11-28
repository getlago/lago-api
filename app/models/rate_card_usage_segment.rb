# frozen_string_literal: true

# One priced segment of a rate card's obligation, with the rate that prices it.
RateCardUsageSegment = Data.define(:billing_segment, :fees) do
  delegate :started_at, :ended_at, :rate_properties, to: :billing_segment

  def rate_model = billing_segment.rate.rate_model

  def units
    fees.sum(BigDecimal(0), &:units)
  end

  def events_count
    fees.sum { |fee| fee.events_count.to_i }
  end

  def amount_cents
    fees.sum(&:amount_cents)
  end
end

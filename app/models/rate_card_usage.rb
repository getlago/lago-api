# frozen_string_literal: true

# One rate card's obligation, with fees from its eligible pricing slices.
RateCardUsage = Data.define(:contract_rate_card, :obligation, :billing_segment, :rate_phase, :fees) do
  def units
    fees.sum(BigDecimal(0), &:units)
  end

  def events_count
    fees.sum { |fee| fee.events_count.to_i }
  end

  def amount_cents
    fees.sum(&:amount_cents)
  end

  def taxes_amount_cents
    fees.sum(&:taxes_amount_cents)
  end

  def rate_source
    billing_segment.rate_override ? "phase_override" : "rate"
  end
end

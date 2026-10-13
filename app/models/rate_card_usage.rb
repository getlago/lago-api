# frozen_string_literal: true

# One rate card's usage on its open billing window. A card with pricing groups has one fee per group.
RateCardUsage = Data.define(:contract_rate_card, :billing_segment, :rate_phase, :fees, :invoice_id) do
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

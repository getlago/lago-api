# frozen_string_literal: true

# One rate card's obligation, with fees from its eligible pricing slices.
RateCardUsage = Data.define(:contract_rate_card, :obligation, :rate_phase, :fees) do
  delegate :properties, to: :rate, prefix: true

  def started_at = obligation.segments.first.started_at
  def ended_at = BillingSegment.inclusive_end(obligation.segments.last.ended_at)

  # Singular pricing metadata represents the first segment for legacy consumers.
  def rate = obligation.cycle.phase.rate_override || obligation.segments.first.rate

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

  # A cycle has one phase: its segments can use different catalog rates, but share one rate source.
  def rate_source
    obligation.cycle.phase.rate_override ? "phase_override" : "rate"
  end
end

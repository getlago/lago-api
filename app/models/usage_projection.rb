# frozen_string_literal: true

UsageProjection = Data.define(:units, :amount_cents, :pricing_unit_amount_cents, :presentation_breakdowns) do
  def self.zero(pricing_unit_amount_cents: nil)
    new(units: BigDecimal(0), amount_cents: 0, pricing_unit_amount_cents:, presentation_breakdowns: [])
  end

  def +(other)
    with(
      units: units + other.units,
      amount_cents: amount_cents + other.amount_cents,
      pricing_unit_amount_cents: sum_pricing_unit_amount_cents(other),
      presentation_breakdowns: presentation_breakdowns + other.presentation_breakdowns
    )
  end

  private

  def sum_pricing_unit_amount_cents(other)
    if pricing_unit_amount_cents.nil? && other.pricing_unit_amount_cents.nil?
      nil
    else
      pricing_unit_amount_cents.to_i + other.pricing_unit_amount_cents.to_i
    end
  end
end

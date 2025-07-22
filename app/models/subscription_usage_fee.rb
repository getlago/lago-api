# frozen_string_literal: true

class SubscriptionUsageFee
  attr_reader :fees, :from_datetime, :to_datetime, :charges_duration_in_days

  def initialize(fees:, from_datetime:, to_datetime:, charges_duration_in_days: nil)
    @fees = fees
    @from_datetime = from_datetime
    @to_datetime = to_datetime
    @charges_duration_in_days = charges_duration_in_days
  end

  def current_amount_cents
    fees.sum(&:amount_cents)
  end

  def projected_amount_cents
    return current_amount_cents if recurring?
    (time_ratio > 0) ? (current_amount_cents / BigDecimal(time_ratio.to_s)).round.to_i : 0
  end

  def current_units
    fees.sum { |f| BigDecimal(f.units) }
  end

  def projected_units
    return current_units if recurring?
    (time_ratio > 0) ? (current_units / BigDecimal(time_ratio.to_s)).round(2) : BigDecimal("0")
  end

  private

  def time_ratio
    from_date = from_datetime.to_date
    to_date = to_datetime.to_date
    current_date = Time.current.to_date

    total_days = (to_date - from_date).to_i + 1

    charges_duration = charges_duration_in_days || total_days

    return 1.0 if current_date >= to_date
    return 0.0 if current_date < from_date

    days_passed = (current_date - from_date).to_i + 1

    ratio = days_passed.fdiv(charges_duration)
    ratio.clamp(0.0, 1.0)
  end

  def recurring?
    fees.first&.charge&.billable_metric&.recurring?
  end
end

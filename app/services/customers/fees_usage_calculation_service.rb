# frozen_string_literal: true

module Customers
  class FeesUsageCalculationService
    attr_reader :fees

    def initialize(fees)
      @fees = fees
    end
    
    def current_amount_cents
      fees.sum(&:amount_cents)
    end

    def projected_amount_cents
      ratio = calculate_time_ratio(fees.first.properties["from_datetime"], fees.first.properties["to_datetime"])

      return current_amount_cents if recurring?
      ratio > 0 ? (current_amount_cents / BigDecimal(ratio.to_s)).round.to_i : 0
    end

    def current_units
      fees.sum { |f| BigDecimal(f.units) }
    end

    def projected_units
      ratio = calculate_time_ratio(fees.first.properties["from_datetime"], fees.first.properties["to_datetime"])
      current_units = fees.sum { |f| BigDecimal(f.units) }

      return current_units if recurring?
      ratio > 0 ? (current_units / BigDecimal(ratio.to_s)).round(2) : BigDecimal('0')
    end

    private

    def calculate_time_ratio(from_datetime, to_datetime, charges_duration_in_days)
      from_date = from_datetime.to_date
      to_date = to_datetime.to_date
      current_date = Date.current

      total_days = (to_date - from_date).to_i + 1

      charges_duration = charges_duration_in_days || total_days

      return 1.0 if current_date >= to_date
      return 0.0 if current_date < from_date

      days_passed = (current_date - from_date).to_i + 1

      ratio = days_passed.to_f / charges_duration
      ratio.clamp(0.0, 1.0)
    end

    def recurring?
      fees.first.charge.billable_metric.recurring?
    end
  end
end
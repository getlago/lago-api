# frozen_string_literal: true

# How a golden row's expected value is compared with what the API returned. The single place that
# knows three things:
#
#   1. WHERE a field lives in the payload  (fee_type is nested at item.type; dotted paths nest)
#   2. HOW it is compared                  (cents exactly, decimals numerically, datetimes parsed)
#   3. WHAT the failure says               (subject, field, expected, actual — in that order)
#
# Comparison semantics, and why they differ:
#
#   exact     *_amount_cents and everything else. Cents ARE the behaviour; a penny is a bug.
#   numeric   units, precise_unit_amount, total_aggregated_units, taxes_rate. These carry a
#             serializer-chosen string format, so "15.0" and "15.00" are the same behaviour
#             expressed twice. Compared as BigDecimal.
#   datetime  from_date, to_date. "Z" and "+00:00" are the same instant.
module GoldenComparison
  module_function

  NUMERIC_FIELDS = %w[units precise_unit_amount total_aggregated_units taxes_rate].freeze
  DATETIME_FIELDS = %w[from_date to_date].freeze

  # V1::FeeSerializer nests the fee type and item identity under `item`, and
  # V1::Customers::ChargeUsageSerializer nests the charge's configuration under `charge`. Rows use
  # flat names. `charge_model` is unambiguous: no fee payload carries one, so the path is safe to
  # apply globally.
  FIELD_PATHS = {
    "fee_type" => %i[item type],
    "item_code" => %i[item code],
    "item_type" => %i[item item_type],
    "charge_model" => %i[charge charge_model]
  }.freeze

  def semantics(field)
    return :datetime if DATETIME_FIELDS.include?(field)
    return :numeric if NUMERIC_FIELDS.include?(field)
    :exact
  end

  # Dotted paths reach into a nested payload section, e.g. billing_configuration.invoice_grace_period.
  def read(payload, field)
    path = FIELD_PATHS[field] || field.to_s.split(".").map(&:to_sym)
    payload.dig(*path)
  end

  def equal?(field, expected, actual)
    case semantics(field)
    when :datetime
      return false if actual.nil?
      parse_time(expected) == parse_time(actual)
    when :numeric
      return false if actual.nil?
      BigDecimal(actual.to_s) == BigDecimal(expected.to_s)
    else
      actual == expected
    end
  end

  def parse_time(value)
    Time.zone.parse(value.to_s) or raise ArgumentError, "golden row: unparseable timestamp #{value.inspect}"
  end

  def message(subject, field, expected, actual)
    prefix = subject.presence ? "#{subject}: " : ""
    "#{prefix}#{field} expected #{expected.inspect}, got #{actual.inspect}"
  end

  # Raises on the FIRST mismatch, naming the subject so a failure is locatable without opening the
  # row. Returns the fields it checked, so a caller can prove none were skipped.
  def assert_fields!(subject, expected, payload)
    expected.each do |field, value|
      actual = read(payload, field)
      next if equal?(field, value, actual)

      raise RSpec::Expectations::ExpectationNotMetError, message(subject, field, value, actual)
    end

    expected.keys
  end

  # Picks which of several payloads a row means, as opposed to asserting on one already chosen.
  # Absent keys do not disqualify a candidate.
  def matches?(expected, payload, keys)
    keys.all? do |key|
      next true unless expected.key?(key)
      equal?(key, expected[key], read(payload, key))
    end
  end
end

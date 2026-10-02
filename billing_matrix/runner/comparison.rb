# frozen_string_literal: true

require "bigdecimal"
require "time"

require_relative "errors"

module BillingMatrix
  # A pure function of two plain hashes: `expected` (straight off a Row) and `observed`
  # (straight off Observe). Neither side carries AR objects, ids, or anything volatile, so this
  # file has no Rails dependency and is testable in isolation.
  #
  # Ported from the previous comparison helper, without RSpec matchers, plus two corrections
  # logged as findings against the old harness:
  #
  #   - two OBSERVED fees sharing the same identity (fee_type, item_code, item_type, from_date,
  #     to_date), or an expected fee whose given identity fields match more than one observed fee,
  #     is an AmbiguousFeeIdentity error — never a silent fallback to a weaker assertion.
  #   - a key present in `expected` and absent from `observed` is always a mismatch, never a skip.
  module Comparison
    NUMERIC_FIELDS = %w[units precise_unit_amount total_aggregated_units taxes_rate].freeze
    DATETIME_FIELDS = %w[from_date to_date].freeze
    FEE_IDENTITY_FIELDS = %w[fee_type item_code item_type from_date to_date].freeze

    # Raised, not recorded as a mismatch: if two fees cannot be told apart, the row's
    # assertion is undefined rather than wrong, and quietly weakening it to a count is
    # how the old harness stopped noticing fee-level defects.
    AmbiguousFeeIdentity = Class.new(Error)

    Result = Struct.new(:mismatches) do
      def match?
        mismatches.empty?
      end
    end

    module_function

    def call(expected:, observed:)
      mismatches = []
      compare_hash(deep_stringify(expected), deep_stringify(observed), "", mismatches)
      Result.new(mismatches)
    end

    def semantics(field)
      return :datetime if DATETIME_FIELDS.include?(field)
      return :numeric if NUMERIC_FIELDS.include?(field)
      :exact
    end

    def equal?(field, expected, observed)
      case semantics(field)
      when :datetime
        return false if observed.nil?
        # Zone-aware parsing needs ActiveSupport; this file loads no Rails, and both sides
        # are already absolute instants by the time they get here.
        Time.parse(expected.to_s) == Time.parse(observed.to_s) # rubocop:disable Rails/TimeZone
      when :numeric
        return false if observed.nil?
        BigDecimal(observed.to_s) == BigDecimal(expected.to_s)
      else
        observed == expected
      end
    end

    def compare_hash(expected, observed, path, mismatches)
      expected.each do |key, exp_val|
        sub_path = path.empty? ? key : "#{path}.#{key}"

        if key == "fees" && exp_val.is_a?(Array)
          observed_fees = observed.is_a?(Hash) ? observed["fees"] : nil
          compare_fees(exp_val, observed_fees, sub_path, mismatches)
          next
        end

        unless observed.is_a?(Hash) && observed.key?(key)
          mismatches << {path: sub_path, expected: exp_val, observed: nil}
          next
        end

        obs_val = observed[key]

        if exp_val.is_a?(Hash)
          compare_hash(exp_val, obs_val, sub_path, mismatches)
        else
          mismatches << {path: sub_path, expected: exp_val, observed: obs_val} unless equal?(key, exp_val, obs_val)
        end
      end
    end

    # Fees are matched by content identity, not by array position: an expected fee is checked
    # against whichever observed fee shares its identity fields, wherever that fee sits in the
    # invoice's fee list.
    def compare_fees(expected_fees, observed_fees, path, mismatches)
      if observed_fees.nil?
        mismatches << {path: path, expected: expected_fees, observed: nil}
        return
      end

      assert_no_identity_collisions!(observed_fees, path)

      expected_fees.each_with_index do |expected_fee, index|
        fee_path = "#{path}[#{index + 1}]"
        candidates = observed_fees.select { |fee| fee_matches_identity?(expected_fee, fee) }

        if candidates.empty?
          mismatches << {path: fee_path, expected: expected_fee, observed: nil}
          next
        end

        if candidates.length > 1
          raise AmbiguousFeeIdentity,
            "#{fee_path}: expected fee #{expected_fee.inspect} matches #{candidates.length} observed fees " \
            "on the identity fields given (#{FEE_IDENTITY_FIELDS.select { |f| expected_fee.key?(f) }.join(", ")}) " \
            "— the row must assert enough identity fields to tell them apart"
        end

        compare_hash(expected_fee, candidates.first, fee_path, mismatches)
      end
    end

    def assert_no_identity_collisions!(observed_fees, path)
      seen = {}
      observed_fees.each_with_index do |fee, index|
        identity = fee_identity(fee)
        collision_index = seen[identity]

        if collision_index
          raise AmbiguousFeeIdentity,
            "#{path}: observed fees at index #{collision_index} and #{index} share the same identity " \
            "#{FEE_IDENTITY_FIELDS.zip(identity).to_h.inspect} — cannot tell which expectation refers to which fee"
        end

        seen[identity] = index
      end
    end

    def fee_identity(fee)
      FEE_IDENTITY_FIELDS.map { |field| fee[field] }
    end

    def fee_matches_identity?(expected_fee, observed_fee)
      FEE_IDENTITY_FIELDS.all? do |field|
        next true unless expected_fee.key?(field)
        equal?(field, expected_fee[field], observed_fee[field])
      end
    end

    def deep_stringify(value)
      case value
      when Hash
        # index_with is ActiveSupport, and this file loads no Rails.
        value.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) } # rubocop:disable Rails/IndexWith
      when Array
        value.map { |v| deep_stringify(v) }
      else
        value
      end
    end
  end
end

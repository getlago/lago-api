# frozen_string_literal: true

module ContractRateCards
  class UnitsHistory
    attr_reader :units_by_timestamp

    def initialize(terms:, changes:)
      @terms = terms.to_a
      dated_units = @terms.to_h { [it.starts_at.utc, it.units] }
      immediate_units = changes.to_h { |timestamp, units| [timestamp.utc, units] }
      @units_by_timestamp = dated_units.merge(immediate_units).sort.to_h.freeze
    end

    def units_at(timestamp)
      units_by_timestamp.select { |starts_at, _| starts_at <= timestamp }.values.last
    end

    def scheduled_term_at(timestamp)
      terms.select { it.next_billing_cycle? && it.starts_at > timestamp }
        .min_by { [it.starts_at, it.created_at, it.id] }
    end

    private

    attr_reader :terms
  end
end

# frozen_string_literal: true

module ContractRateCards
  class UnitsHistory
    ScheduledTerm = Data.define(:term, :starts_at) do
      delegate :units, :effective_date, :created_at, :id, to: :term
    end
    private_constant :ScheduledTerm

    attr_reader :units_by_timestamp

    def initialize(terms:, changes:, schedule:)
      @scheduled_terms = resolve_scheduled_terms(terms, schedule)
      @units_by_timestamp = build_timeline(terms, changes).freeze
    end

    def units_at(timestamp)
      units = nil
      units_by_timestamp.each do |starts_at, quantity|
        break if starts_at > timestamp

        units = quantity
      end
      units
    end

    def scheduled_term_at(timestamp)
      scheduled_terms.find { |scheduled_term| scheduled_term.starts_at > timestamp }
    end

    def pending_terms_at(timestamp)
      scheduled_terms.select { |scheduled_term| scheduled_term.starts_at > timestamp }.map(&:term)
    end

    private

    attr_reader :scheduled_terms

    def resolve_scheduled_terms(terms, schedule)
      resolved_terms = terms.filter_map do |term|
        next unless term.next_billing_cycle?

        starts_at = schedule.next_segment_start(after_date: term.effective_date)
        ScheduledTerm.new(term:, starts_at:) if starts_at
      end

      resolved_terms.sort_by { |scheduled_term| [scheduled_term.starts_at, scheduled_term.created_at, scheduled_term.id] }
    end

    def build_timeline(terms, changes)
      timeline = {}
      terms.each do |term|
        next unless term.current_billing_cycle?

        timeline[term.starts_at.utc] = term.units
      end

      scheduled_terms.each do |scheduled_term|
        timeline[scheduled_term.starts_at.utc] = scheduled_term.units
      end

      # An immediate change overrides dated units at the same instant.
      changes.each do |timestamp, units|
        timeline[timestamp.utc] = units
      end

      timeline.sort.to_h
    end
  end
end

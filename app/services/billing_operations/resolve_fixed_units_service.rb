# frozen_string_literal: true

module BillingOperations
  # Resolve quantities before pricing so tiers and minimums are applied once per priced window.
  class ResolveFixedUnitsService < BaseService
    Result = BaseResult[:segments]
    UnitsInterval = Data.define(:started_at, :ended_at, :units)
    private_constant :UnitsInterval

    def initialize(segments:, cycle:, operation: nil, units_histories: {})
      @segments = segments
      @cycle = cycle
      @operation = operation
      @units_histories = units_histories
      super
    end

    def call
      validate_saved_units if operation&.units_change?
      return result if result.failure?

      result.segments = segments.filter_map do |segment|
        next segment unless segment.contract_rate_card.product.fixed?

        if operation&.units_change?
          resolve_adjustment(segment)
        elsif segment.contract_rate_card.rate_card.advance?
          segment.units = units_at(segment, segment.started_at)
          segment
        else
          resolve_arrears(segment)
        end
      end
      result
    end

    private

    attr_reader :segments, :cycle, :operation, :units_histories

    def units_at(segment, timestamp)
      history_for(segment).units_at(timestamp) || 0.to_d
    end

    def history_for(segment)
      card = segment.contract_rate_card
      units_histories[card.id] ||= ContractRateCardUnitsHistoryQuery.call!(organization: card.organization,
        contract_rate_cards: [card]).histories.fetch(card.id)
    end

    def resolve_arrears(segment)
      intervals = units_intervals(segment)
      segment.units = weighted_units(intervals)
      if intervals.many? && segment.contract_rate_card.rate_card.proration?
        segment.proration_ratio = elapsed_ratio(intervals.first.started_at, intervals.last.ended_at)
      end
      segment.units_intervals = serialize_intervals(intervals)
      segment
    end

    def units_intervals(segment)
      from = segment.started_at
      to = BillingSegment.exclusive_end(segment.ended_at)
      history = history_for(segment)
      changes = history.units_by_timestamp.keys.select { it > from && it < to }
      boundaries = [from, *changes, to]
      units = history.units_at(from) || 0.to_d

      boundaries.each_cons(2).map do |start, finish|
        units = history.units_by_timestamp.fetch(start, units)
        UnitsInterval.new(started_at: start, ended_at: finish, units:)
      end
    end

    def weighted_units(intervals)
      duration = elapsed_seconds(intervals.first.started_at, intervals.last.ended_at)

      # Keep decimal quantities unrounded; the fee calculator rounds the resulting amount.
      intervals.sum do |interval|
        interval.units * elapsed_seconds(interval.started_at, interval.ended_at) / duration
      end
    end

    def serialize_intervals(intervals)
      intervals.map do |interval|
        {started_at: interval.started_at.iso8601(6), ended_at: interval.ended_at.iso8601(6), units: interval.units.to_s}
      end
    end

    def resolve_adjustment(segment)
      timestamp = operation.billing_at
      segment.started_at = timestamp
      segment.units = units_at(segment, timestamp)
      segment.prepaid_units = prepaid_units_at(timestamp)
      return if segment.units <= segment.prepaid_units

      segment.proration_ratio = if segment.contract_rate_card.rate_card.proration?
        elapsed_ratio(timestamp, BillingSegment.exclusive_end(segment.ended_at))
      else
        1.to_d
      end
      segment
    end

    def elapsed_ratio(from, to)
      window = cycle.calendar.interval_containing(from)
      elapsed_seconds(from, to) / elapsed_seconds(window.begin, window.end)
    end

    def elapsed_seconds(from, to)
      (to.to_r - from.to_r).to_d(30)
    end

    def prepaid_units_at(timestamp)
      quantities = completed_advance_operations.flat_map do |previous|
        saved_segments = previous.segments.reject { |segment| segment.units.nil? }
        prepaid_units_from_segments(saved_segments, timestamp)
      end
      quantities.max || 0.to_d
    end

    def validate_saved_units
      completed_advance_operations.each do |previous|
        next unless previous.invoice_id

        if previous.segments.empty? || previous.segments.any? { |segment| segment.units.nil? }
          return result.single_validation_failure!(field: :operation, error_code: "missing_saved_units")
        end
      end
    end

    def prepaid_units_from_segments(saved_segments, timestamp)
      saved_segments.filter_map do |segment|
        segment.units if segment.started_at <= timestamp && timestamp < segment.ended_at
      end
    end

    def completed_advance_operations
      @completed_advance_operations ||= begin
        renewals = operation.contract_rate_card.billing_operations.completed
          .where(organization_id: operation.organization_id, target_cycle_started_at: operation.target_cycle_started_at,
            cancelled_at: nil, action_type: "renew_fixed_advance")
        renewals.or(operation.reconciliations.completed.where(cancelled_at: nil).unscope(:order))
          .includes(:segments).to_a
      end
    end
  end
end

# frozen_string_literal: true

module BillingOperations
  # Resolve quantities before pricing so tiers and minimums are applied once per priced window.
  class ResolveFixedUnitsService < BaseService
    Result = BaseResult[:segments]
    UnitsInterval = Data.define(:started_at, :ended_at, :units)
    private_constant :UnitsInterval

    def initialize(segments:, cycle:, operation: nil)
      @segments = segments
      @cycle = cycle
      @operation = operation
      super
    end

    def call
      result.segments = segments.filter_map do |segment|
        next segment unless segment.contract_rate_card.product.fixed?

        if operation&.action_type == "adjust_fixed_advance"
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

    attr_reader :segments, :cycle, :operation

    def units_at(segment, timestamp)
      ContractRateCards::UnitsAtService.call!(contract_rate_card: segment.contract_rate_card, timestamp:).units || 0.to_d
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
      changes = segment.contract_rate_card.terms.map(&:starts_at).select { it > from && it < to }.uniq.sort
      boundaries = [from, *changes, to]

      boundaries.each_cons(2).map do |start, finish|
        UnitsInterval.new(started_at: start, ended_at: finish, units: units_at(segment, start))
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
      completed_advance_operations.flat_map do |previous|
        if previous.pricing_segments
          prepaid_units_from_snapshot(previous.pricing_segments, timestamp)
        else
          prepaid_units_from_fees(previous.invoice, timestamp)
        end
      end.max || 0.to_d
    end

    def completed_advance_operations
      operation.contract_rate_card.billing_operations.completed
        .where(organization_id: operation.organization_id, target_cycle_started_at: operation.target_cycle_started_at,
          cancelled_at: nil, action_type: %w[renew_fixed_advance adjust_fixed_advance])
    end

    def prepaid_units_from_snapshot(snapshot, timestamp)
      snapshot.filter_map do |input|
        input["units"].to_d if timestamp.between?(Time.iso8601(input.fetch("started_at")), Time.iso8601(input.fetch("ended_at")))
      end
    end

    def prepaid_units_from_fees(invoice, timestamp)
      return [] unless invoice

      invoice.fees.where(organization_id: operation.organization_id, contract_rate_card_id: operation.contract_rate_card_id,
        pay_in_advance: true).pluck(:units, :properties).filter_map do |units, properties|
        from = properties["from_datetime"]
        to = properties["to_datetime"]
        units if from && to && timestamp.between?(Time.iso8601(from), Time.iso8601(to))
      end
    end
  end
end

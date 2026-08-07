# frozen_string_literal: true

module UsageProjections
  # Compares the RisingWave-fed projections against the events-store
  # aggregation, charge by charge, for subscriptions that have projection
  # rows in their current period. Charge-level totals are compared (the sum
  # across filter buckets equals the plain aggregation over all the metric's
  # events, since every event lands in exactly one bucket).
  #
  # Run in shadow while reads still come from the events store; a sustained
  # clean report across period rollovers is what justifies enabling
  # LAGO_RISINGWAVE_USAGE_ENABLED.
  class ParityCheckService < BaseService
    Result = BaseResult[:checked_count, :mismatches]

    TOLERANCE = BigDecimal("0.0001")

    def initialize(limit: 100)
      @limit = limit

      super
    end

    def call
      mismatches = []
      checked = 0

      subscription_ids = UsageRealtimeProjection.covering(Time.current)
        .distinct.limit(limit).pluck(:subscription_id)

      Subscription.where(id: subscription_ids).includes(plan: :charges).find_each do |subscription|
        projections = UsageRealtimeProjection.covering(Time.current)
          .where(subscription_id: subscription.id)
          .group_by(&:charge_id)

        projections.each do |charge_id, rows|
          charge = subscription.plan.charges.find { |c| c.id == charge_id }
          next if charge.nil? || !comparable?(charge)

          checked += 1
          expected = events_store_total(subscription, charge, rows.first)
          next if expected.nil?

          actual = (charge.billable_metric.aggregation_type == "count_agg") ?
            rows.sum(&:events_count) :
            rows.sum(&:units)

          if (BigDecimal(actual.to_s) - expected).abs > TOLERANCE
            mismatches << {
              subscription_id: subscription.id,
              charge_id: charge_id,
              code: rows.first.code,
              events_store: expected.to_s,
              projection: actual.to_s
            }
          end
        end
      end

      report(mismatches, checked)

      result.checked_count = checked
      result.mismatches = mismatches
      result
    end

    private

    attr_reader :limit

    def comparable?(charge)
      billable_metric = charge.billable_metric
      %w[count_agg sum_agg].include?(billable_metric.aggregation_type) &&
        !charge.prorated? &&
        !billable_metric.recurring? &&
        billable_metric.expression.blank?
    end

    def events_store_total(subscription, charge, projection_row)
      aggregator_class = (charge.billable_metric.aggregation_type == "count_agg") ?
        BillableMetrics::Aggregations::CountService :
        BillableMetrics::Aggregations::SumService

      aggregation_result = aggregator_class.new(
        event_store_class: Events::Stores::StoreFactory.store_class(organization: charge.billable_metric.organization),
        charge:,
        subscription:,
        boundaries: {
          from_datetime: projection_row.period_charges_from,
          to_datetime: projection_row.period_charges_to,
          charges_from_datetime: projection_row.period_charges_from,
          charges_to_datetime: projection_row.period_charges_to,
          charges_duration: nil
        }
      ).aggregate

      if aggregation_result.failure?
        Rails.logger.warn("[usage_projections] parity check aggregation failed for charge #{charge.id}")
        return nil
      end

      BigDecimal(aggregation_result.aggregation.to_s)
    end

    def report(mismatches, checked)
      if mismatches.empty?
        Rails.logger.info("[usage_projections] parity check OK (#{checked} charges compared)")
      else
        Rails.logger.error("[usage_projections] parity check found #{mismatches.size}/#{checked} mismatches: #{mismatches.first(10).inspect}")
      end
    end
  end
end

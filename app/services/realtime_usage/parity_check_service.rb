# frozen_string_literal: true

module RealtimeUsage
  # Compares the RisingWave-fed usage buckets against the events-store
  # aggregation, charge by charge, over the current billing period computed
  # by Subscriptions::DatesService — the exact window the realtime read path
  # uses. Charge-level totals are compared (the sum across filter buckets
  # equals the plain aggregation over all the metric's events, since every
  # event lands in exactly one bucket).
  #
  # Run in shadow while reads still come from the events store; a sustained
  # clean report across period rollovers is what justifies enabling
  # LAGO_RISINGWAVE_USAGE_ENABLED.
  class ParityCheckService < BaseService
    Result = BaseResult[:checked_count, :mismatches]

    TOLERANCE = BigDecimal("0.0001")
    RECENT_ACTIVITY_WINDOW = 31.days

    def initialize(limit: 100)
      @limit = limit

      super
    end

    def call
      mismatches = []
      checked = 0

      subscription_ids = Clickhouse::UsageBucket.final
        .where("bucket >= ?", RECENT_ACTIVITY_WINDOW.ago)
        .distinct.limit(limit).pluck(:subscription_id)

      Subscription.where(id: subscription_ids).includes(plan: :charges).find_each do |subscription|
        charges_from, charges_to = current_period_window(subscription)
        next if charges_from.nil? || charges_to.nil?

        totals = Clickhouse::UsageBucket.final
          .where(subscription_id: subscription.id)
          .where("bucket >= ? AND bucket <= ?", charges_from.change(min: charges_from.min - charges_from.min % 15), charges_to)
          .group(:charge_id)
          .pluck(Arel.sql("charge_id, sum(events_count), sum(units)"))

        totals.each do |charge_id, events_count, units|
          charge = subscription.plan.charges.find { |c| c.id == charge_id }
          next if charge.nil? || !comparable?(charge)

          checked += 1
          expected = events_store_total(subscription, charge, charges_from, charges_to)
          next if expected.nil?

          actual = (charge.billable_metric.aggregation_type == "count_agg") ? events_count : units

          if (BigDecimal(actual.to_s) - expected).abs > TOLERANCE
            mismatches << {
              subscription_id: subscription.id,
              charge_id: charge_id,
              code: charge.billable_metric.code,
              events_store: expected.to_s,
              buckets: actual.to_s
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

    def current_period_window(subscription)
      dates_service = Subscriptions::DatesService.new_instance(subscription, Time.current, current_usage: true)

      [dates_service.charges_from_datetime, dates_service.charges_to_datetime]
    rescue => e
      Rails.logger.warn("[realtime_usage] parity check could not compute boundaries for subscription #{subscription.id}: #{e.message}")
      [nil, nil]
    end

    def comparable?(charge)
      billable_metric = charge.billable_metric
      %w[count_agg sum_agg].include?(billable_metric.aggregation_type) &&
        !charge.prorated? &&
        !billable_metric.recurring? &&
        billable_metric.expression.blank?
    end

    def events_store_total(subscription, charge, charges_from, charges_to)
      aggregation_result = aggregator_class(charge).new(
        event_store_class: Events::Stores::StoreFactory.store_class(organization: charge.billable_metric.organization),
        charge:,
        subscription:,
        boundaries: {
          from_datetime: charges_from,
          to_datetime: charges_to,
          charges_from_datetime: charges_from,
          charges_to_datetime: charges_to,
          charges_duration: nil
        }
      ).aggregate

      if aggregation_result.failure?
        Rails.logger.warn("[realtime_usage] parity check aggregation failed for charge #{charge.id}")
        return nil
      end

      BigDecimal(aggregation_result.aggregation.to_s)
    end

    def aggregator_class(charge)
      (charge.billable_metric.aggregation_type == "count_agg") ?
        BillableMetrics::Aggregations::CountService :
        BillableMetrics::Aggregations::SumService
    end

    def report(mismatches, checked)
      if mismatches.empty?
        Rails.logger.info("[realtime_usage] parity check OK (#{checked} charges compared)")
      else
        Rails.logger.error("[realtime_usage] parity check found #{mismatches.size}/#{checked} mismatches: #{mismatches.first(10).inspect}")
      end
    end
  end
end

# frozen_string_literal: true

# ============================================================================
# PR #5759 — events pre-filtering — manual console test
#
# Usage:
#   1. Set the two IDs in PART 2 below.
#   2. Paste this whole file into `rails console`, or load it:
#        load "test_pre_filter.rb"
#
# The patches only change the non-`pre_filter_events` (Postgres) path, exactly
# what PR #5759 touches. They live only in the current console session.
# ============================================================================

# ============================================================================
# PART 1 — Monkey-patch PR #5759 into the running process.
# ============================================================================

# 1/4 — EventMatchingService: expose ALL matching filters (not just the best one)
module ChargeFilters
  class EventMatchingService
    def call
      matching_filters = filters.select do |filter|
        filter.to_h.all? do |key, values|
          applicable_event_properties.key?(key) &&
            (applicable_event_properties[key].to_s.in?(values) || values == [ChargeFilterValue::ALL_FILTER_VALUES])
        end
      end

      result.matching_charge_filters = matching_filters
      result.charge_filter = matching_filters.max_by { |filter| filter.to_h.keys.size }
      result
    end

    private

    def applicable_event_properties
      @applicable_event_properties ||= event.properties.slice(*charge.billable_metric.filters.map(&:key))
    end
  end
end

# 2/4 — BaseStore: default "unsupported" so non-Postgres stores fall back
module Events
  module Stores
    class BaseStore
      def distinct_codes_and_property_combinations(codes:, filter_keys:)
        nil
      end
    end
  end
end

# 3/4 — PostgresStore: the single query extracting distinct property combinations
module Events
  module Stores
    class PostgresStore
      def distinct_codes_and_property_combinations(codes:, filter_keys:)
        scope = Event.where(external_subscription_id: subscription.external_id)
          .where(organization_id: subscription.organization.id)
          .where(code: codes)
          .from_datetime(from_datetime)
          .to_datetime(applicable_to_datetime)

        scope
          .select(Arel.sql(<<~SQL.squish))
            DISTINCT events.code AS code,
            coalesce((
              SELECT jsonb_object_agg(props.key, props.value)
              FROM jsonb_each_text(events.properties) AS props(key, value)
              WHERE props.key = ANY(#{filter_keys_array_sql(filter_keys)})
            ), '{}'::jsonb) AS combination
          SQL
          .map { |row| [row.code, parse_combination(row)] }
      end

      def filter_keys_array_sql(filter_keys)
        return "ARRAY[]::text[]" if filter_keys.empty?

        quoted = filter_keys.map { ActiveRecord::Base.connection.quote(it) }.join(", ")
        "ARRAY[#{quoted}]::text[]"
      end

      def parse_combination(row)
        combination = row.read_attribute(:combination)
        return combination if combination.is_a?(Hash)

        combination.present? ? JSON.parse(combination) : {}
      end
    end
  end
end

# 4/4 — BillingPeriodFilterService: precise resolution + stash result for inspection
module Events
  class BillingPeriodFilterService
    def call
      result.charges = deduplicate_filters(charges_and_filters)
      Thread.current[:lago_last_billing_filter] = result.charges # for inspection
      result
    end

    def charges_and_filters_from_event_codes
      combinations = event_store.distinct_codes_and_property_combinations(
        codes: plan_codes,
        filter_keys: billable_metric_filter_keys
      )

      return coarse_charges_and_filters if combinations.nil?

      combinations_by_code = combinations
        .group_by(&:first)
        .transform_values { |rows| rows.map(&:last) }

      result = recurring_event_charges_and_filters

      non_recurring_charges_with_events(combinations_by_code.keys).each do |charge|
        code = charge.billable_metric.code

        combinations_by_code[code].each do |properties|
          event = ::Event.new(code:, properties:)
          matching = ChargeFilters::EventMatchingService.call(charge:, event:).matching_charge_filters

          if matching.empty?
            result[charge.id] << nil
          else
            matching.each { |filter| result[charge.id] << filter.id }
          end
        end
      end

      result
    end

    def coarse_charges_and_filters
      plan.charges.joins(:billable_metric).left_joins(:filters)
        .where(billable_metrics: {code: distinct_event_codes})
        .or(plan.charges.joins(:billable_metric).where(billable_metrics: {recurring: true}))
        .group("charges.id, charge_filters.id")
        .pluck("charges.id", "charge_filters.id")
        .then { group_by_charge_id(it) }
        .then { add_default_filter(it) }
    end

    def recurring_event_charges_and_filters
      plan.charges.joins(:billable_metric).left_joins(:filters)
        .where(billable_metrics: {recurring: true})
        .group("charges.id, charge_filters.id")
        .pluck("charges.id", "charge_filters.id")
        .then { group_by_charge_id(it) }
        .then { add_default_filter(it) }
    end

    def non_recurring_charges_with_events(codes)
      plan.charges
        .joins(:billable_metric)
        .where(billable_metrics: {code: codes, recurring: false})
        .includes(billable_metric: :filters, filters: {values: :billable_metric_filter})
    end

    def billable_metric_filter_keys
      @billable_metric_filter_keys ||= BillableMetricFilter
        .where(billable_metric_id: plan.billable_metrics.select(:id))
        .distinct
        .pluck(:key)
    end
  end
end

puts "✅ PR #5759 patches loaded"

# ============================================================================
# PART 2 — Run a current-usage test against a real subscription.
# ============================================================================
SUBSCRIPTION_ID = "dbbc3fd3-efa4-4fb7-9085-58fd9d9059ea"

subscription = Subscription.find(SUBSCRIPTION_ID)

puts "\norg pre_filter_events?:   #{subscription.organization.pre_filter_events?}"
puts "org clickhouse_events?:   #{subscription.organization.clickhouse_events_store?}"

started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
result = Invoices::CustomerUsageService.call(
  customer: subscription.customer,
  subscription:,
  apply_taxes: false,
  with_cache: false # bypass the cache so you see the patched logic
)
elapsed_s = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at).round(2)

if !result.success?
  puts "❌ #{result.error}"
else
  usage = result.usage
  puts "\n== Pre-filter output (charge_id => [charge_filter_id|nil]) =="
  pp Thread.current[:lago_last_billing_filter]

  puts "\n== Usage =="
  puts "compute duration:   #{elapsed_s} s"
  puts "total_amount_cents: #{usage.total_amount_cents}"
  puts "fees count:         #{usage.fees.size}"
  #puts "fees (units / amount_cents): #{usage.fees.map { |f| "#{f.units} / #{f.amount_cents}" }.join(", ")}"
end
nil

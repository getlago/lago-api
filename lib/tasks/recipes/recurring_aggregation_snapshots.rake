# frozen_string_literal: true

require "csv"
require_relative "../../task_prompt"

RECURRING_SNAPSHOTS_CSV_HEADERS = %w[
  subscription_id
  external_subscription_id
  charge_id
  billable_metric_code
  charge_filter_id
  grouped_by
  snapshot_read
  snapshot_units
  full_scan_units
  snapshot_total_aggregated_units
  full_scan_total_aggregated_units
  snapshot_amount_cents
  full_scan_amount_cents
  snapshot_events_count
  full_scan_events_count
].freeze

RECURRING_SNAPSHOTS_PAY_IN_ADVANCE_AGGREGATION_FIELDS = %i[
  aggregation
  count
  pay_in_advance_aggregation
  full_units_number
  current_aggregation
  max_aggregation
  max_aggregation_with_proration
  units_applied
].freeze

RECURRING_SNAPSHOTS_PAY_IN_ADVANCE_CSV_HEADERS = [
  "subscription_id",
  "external_subscription_id",
  "event_transaction_id",
  "event_timestamp",
  "charge_id",
  "billable_metric_code",
  "charge_filter_id",
  "grouped_by",
  "snapshot_read",
  *RECURRING_SNAPSHOTS_PAY_IN_ADVANCE_AGGREGATION_FIELDS.flat_map { ["snapshot_#{it}", "full_scan_#{it}"] }
].freeze

namespace :recipes do
  namespace :recurring_aggregation_snapshots do
    desc "Compare the current usage and the pay in advance aggregation of recurring charges read from the snapshots with the ones scanning the full history"
    task compare_usage: :environment do
      Rails.logger.level = Logger::Severity::ERROR

      puts "The persisted_recurring_values flag is forced on for the snapshot run and off for the"
      puts "full scan run, whatever it is set to for the organization. Nothing is persisted."
      puts ""

      organization = TaskPrompt.ask_for_organization

      subscriptions = TaskPrompt.ask_for_sampled_subscriptions(organization)
      abort "No subscription to compare." if subscriptions.empty?

      default_path = Rails.root.join("tmp", "recurring_snapshots_comparison_#{organization.id}_#{Time.current.to_i}.csv").to_s
      csv_path = TaskPrompt.ask("CSV output path [#{default_path}]: ")
      csv_path = default_path if csv_path.empty?
      pay_in_advance_csv_path = csv_path.sub(/(\.csv)?\z/, "_pay_in_advance.csv")

      puts ""
      puts "Comparing #{subscriptions.size} subscription(s)"

      csv_rows = []
      pay_in_advance_csv_rows = []
      pay_in_advance_events = 0
      compared = 0
      failed = 0
      without_snapshot = 0
      mismatching = 0

      subscriptions.each do |subscription|
        comparison = RecurringAggregationSnapshots::CompareUsageService.call(subscription:)

        unless comparison.success?
          failed += 1
          puts "  Subscription #{subscription.id}: FAILED (#{comparison.error})"
          next
        end

        csv_rows.concat(recurring_snapshots_csv_rows(subscription, comparison))
        recurring_snapshots_print_comparison(subscription, comparison)

        pay_in_advance = RecurringAggregationSnapshots::ComparePayInAdvanceService.call(subscription:)

        unless pay_in_advance.success?
          failed += 1
          puts "      pay in advance: FAILED (#{pay_in_advance.error})"
          next
        end

        compared += 1
        pay_in_advance_events += pay_in_advance.compared_events_count
        without_snapshot += 1 if comparison.snapshot_charges_count.zero? && pay_in_advance.rows.none?(&:snapshot_read)
        mismatching += 1 if comparison.differences.any? || pay_in_advance.differences.any?

        pay_in_advance_csv_rows.concat(recurring_snapshots_pay_in_advance_csv_rows(subscription, pay_in_advance))
        recurring_snapshots_print_pay_in_advance_comparison(pay_in_advance)
      end

      CSV.open(csv_path, "w") do |csv|
        csv << RECURRING_SNAPSHOTS_CSV_HEADERS
        csv_rows.each { csv << it }
      end

      CSV.open(pay_in_advance_csv_path, "w") do |csv|
        csv << RECURRING_SNAPSHOTS_PAY_IN_ADVANCE_CSV_HEADERS
        pay_in_advance_csv_rows.each { csv << it }
      end

      puts ""
      puts "Summary"
      puts "  subscriptions compared:         #{compared} (#{failed} failed)"
      puts "  subscriptions without snapshot: #{without_snapshot} (full scan on both sides, nothing compared)"
      puts "  subscriptions mismatching:      #{mismatching}"
      puts "  pay in advance events replayed: #{pay_in_advance_events}"
      puts "  per-leaf CSV: #{csv_path}"
      puts "  per-event pay in advance CSV: #{pay_in_advance_csv_path}"
      puts ""
      puts(if compared.zero?
        "No subscription could be compared."
      elsif compared == without_snapshot
        "No subscription read a snapshot: this run says nothing about parity."
      elsif mismatching.zero?
        "No mismatch over the charges and events read from a snapshot."
      else
        "Mismatches detected, investigate before enabling the organization."
      end)
    end
  end
end

def recurring_snapshots_print_comparison(subscription, comparison)
  status = if comparison.snapshot_charges_count.zero?
    "NO SNAPSHOT"
  elsif comparison.differences.any?
    "DIFF"
  else
    "OK"
  end

  puts "  Subscription #{subscription.id} (#{subscription.external_id}): " \
       "#{comparison.snapshot_charges_count}/#{comparison.compared_charges_count} charges read from a snapshot, " \
       "#{comparison.differences.size} mismatching leaf/leaves [#{status}]"

  comparison.differences.group_by(&:charge_id).each do |charge_id, rows|
    puts "      charge #{rows.first.billable_metric_code} (#{charge_id}): #{rows.size} mismatching leaf/leaves, see the CSV"
  end
end

def recurring_snapshots_csv_rows(subscription, comparison)
  comparison.rows.map do |row|
    [
      subscription.id,
      subscription.external_id,
      row.charge_id,
      row.billable_metric_code,
      row.charge_filter_id,
      row.grouped_by.to_json,
      row.snapshot_read,
      recurring_snapshots_csv_value(row.snapshot.units),
      recurring_snapshots_csv_value(row.full_scan.units),
      recurring_snapshots_csv_value(row.snapshot.total_aggregated_units),
      recurring_snapshots_csv_value(row.full_scan.total_aggregated_units),
      row.snapshot.amount_cents,
      row.full_scan.amount_cents,
      row.snapshot.events_count,
      row.full_scan.events_count
    ]
  end
end

def recurring_snapshots_print_pay_in_advance_comparison(comparison)
  return if comparison.compared_charges_count.zero?

  puts "      pay in advance: #{comparison.compared_events_count} event(s) replayed, " \
       "#{comparison.rows.count(&:snapshot_read)} bucket(s) read from a snapshot, " \
       "#{comparison.differences.size} mismatching"

  comparison.differences.group_by(&:charge_id).each do |charge_id, rows|
    puts "      charge #{rows.first.billable_metric_code} (#{charge_id}): #{rows.size} mismatching event bucket(s), see the CSV"
  end
end

def recurring_snapshots_pay_in_advance_csv_rows(subscription, comparison)
  comparison.rows.map do |row|
    [
      subscription.id,
      subscription.external_id,
      row.event_transaction_id,
      row.event_timestamp.iso8601(3),
      row.charge_id,
      row.billable_metric_code,
      row.charge_filter_id,
      row.grouped_by.to_json,
      row.snapshot_read,
      *RECURRING_SNAPSHOTS_PAY_IN_ADVANCE_AGGREGATION_FIELDS.flat_map do |field|
        [row.snapshot, row.full_scan].map { recurring_snapshots_csv_value(it.public_send(field)) }
      end
    ]
  end
end

def recurring_snapshots_csv_value(value)
  value.is_a?(BigDecimal) ? value.to_s("F") : value&.to_s
end

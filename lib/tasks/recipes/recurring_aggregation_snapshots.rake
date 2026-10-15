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

namespace :recipes do
  namespace :recurring_aggregation_snapshots do
    desc "Compare the current usage of recurring charges read from the snapshots with the one scanning the full history"
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

      puts ""
      puts "Comparing #{subscriptions.size} subscription(s)"

      csv_rows = []
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

        compared += 1
        without_snapshot += 1 if comparison.snapshot_charges_count.zero?
        mismatching += 1 if comparison.differences.any?

        csv_rows.concat(recurring_snapshots_csv_rows(subscription, comparison))
        recurring_snapshots_print_comparison(subscription, comparison)
      end

      CSV.open(csv_path, "w") do |csv|
        csv << RECURRING_SNAPSHOTS_CSV_HEADERS
        csv_rows.each { csv << it }
      end

      puts ""
      puts "Summary"
      puts "  subscriptions compared:         #{compared} (#{failed} failed)"
      puts "  subscriptions without snapshot: #{without_snapshot} (full scan on both sides, nothing compared)"
      puts "  subscriptions mismatching:      #{mismatching}"
      puts "  per-leaf CSV: #{csv_path}"
      puts ""
      puts(if compared.zero?
        "No subscription could be compared."
      elsif compared == without_snapshot
        "No subscription read a snapshot: this run says nothing about parity."
      elsif mismatching.zero?
        "No mismatch over the charges read from a snapshot."
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
      row.snapshot.units.to_s("F"),
      row.full_scan.units.to_s("F"),
      row.snapshot.total_aggregated_units.to_s("F"),
      row.full_scan.total_aggregated_units.to_s("F"),
      row.snapshot.amount_cents,
      row.full_scan.amount_cents,
      row.snapshot.events_count,
      row.full_scan.events_count
    ]
  end
end

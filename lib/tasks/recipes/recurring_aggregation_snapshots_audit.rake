# frozen_string_literal: true

require "csv"
require_relative "../../task_prompt"

RECURRING_SNAPSHOTS_AUDIT_CSV_HEADERS = %w[
  subscription_id
  external_subscription_id
  charge_id
  billable_metric_code
  charge_filter_id
  grouped_by
  to_datetime
  watermark
  bounded
  stored_units
  recomputed_units
  stored_events_count
  recomputed_events_count
].freeze

namespace :recipes do
  namespace :recurring_aggregation_snapshots do
    desc "Check the snapshots of the latest closed period against the events up to their watermark"
    task audit: :environment do
      Rails.logger.level = Logger::Severity::ERROR

      puts "The latest closed period of each recurring charge is computed again at the watermark of its"
      puts "snapshots, and compared with the stored rows. Nothing is persisted."
      puts ""

      organization = TaskPrompt.ask_for_organization

      subscriptions = TaskPrompt.ask_for_sampled_subscriptions(organization)
      abort "No subscription to audit." if subscriptions.empty?

      default_path = Rails.root.join("tmp", "recurring_snapshots_audit_#{organization.id}_#{Time.current.to_i}.csv").to_s
      csv_path = TaskPrompt.ask("CSV output path [#{default_path}]: ")
      csv_path = default_path if csv_path.empty?

      puts ""
      puts "Auditing #{subscriptions.size} subscription(s)"

      csv_rows = []
      audited = 0
      failed = 0
      without_snapshot = 0
      mismatching = 0
      unbounded_differences = 0
      without_marker = 0
      without_invoice = 0

      subscriptions.each do |subscription|
        audit = RecurringAggregationSnapshots::AuditService.call(subscription:)

        unless audit.success?
          failed += 1
          puts "  Subscription #{subscription.id}: FAILED (#{audit.error})"
          next
        end

        audited += 1
        status = recurring_snapshots_audit_status(audit)
        without_snapshot += 1 if status == "NO SNAPSHOT"
        mismatching += 1 if status == "DIFF"
        unbounded_differences += audit.differences.count { !it.bounded }
        without_marker += audit.charges_without_marker.size
        without_invoice += audit.charges_without_invoice.size

        csv_rows.concat(recurring_snapshots_audit_csv_rows(subscription, audit))
        recurring_snapshots_audit_print(subscription, audit, status)
      end

      CSV.open(csv_path, "w") do |csv|
        csv << RECURRING_SNAPSHOTS_AUDIT_CSV_HEADERS
        csv_rows.each { csv << it }
      end

      puts ""
      puts "Summary"
      puts "  subscriptions audited:          #{audited} (#{failed} failed)"
      puts "  subscriptions without snapshot: #{without_snapshot}"
      puts "  subscriptions mismatching:      #{mismatching}"
      puts "  charges without period marker:  #{without_marker}"
      puts "  charges without period invoice: #{without_invoice} (not audited)"
      puts "  weighted sum differences:       #{unbounded_differences} (not bounded by the watermark, see below)"
      puts "  per-leaf CSV: #{csv_path}"
      puts ""
      puts "A weighted sum snapshot is not bounded by its watermark: an event of the period ingested after the"
      puts "invoice shows as a difference. A charge edited since the period was invoiced can differ too."
      puts ""
      puts(if audited.zero?
        "No subscription could be audited."
      elsif audited == without_snapshot
        "No subscription has a snapshot: this run says nothing about the write path."
      elsif mismatching.positive?
        "Mismatches detected, investigate the write path."
      elsif without_invoice.positive?
        "Some snapshots have no invoice for their period and were not audited, investigate the write path."
      else
        "The stored snapshots match their events."
      end)
    end
  end
end

def recurring_snapshots_audit_status(audit)
  if audit.snapshot_charges_count.zero?
    "NO SNAPSHOT"
  elsif audit.differences.any?(&:bounded) || audit.charges_without_marker.any?
    "DIFF"
  elsif audit.charges_without_invoice.any?
    "INCOMPLETE"
  else
    "OK"
  end
end

def recurring_snapshots_audit_print(subscription, audit, status)
  puts "  Subscription #{subscription.id} (#{subscription.external_id}): " \
       "#{audit.snapshot_charges_count}/#{audit.audited_charges_count} charges with a snapshot, " \
       "#{audit.differences.size} differing leaf/leaves [#{status}]"

  audit.charges_without_marker.each do |charge_id|
    puts "      charge #{charge_id}: no default bucket row in its latest period"
  end
  audit.charges_without_invoice.each do |charge_id|
    puts "      charge #{charge_id}: no invoice for its latest period, not audited"
  end
  audit.differences.group_by(&:charge_id).each do |charge_id, rows|
    puts "      charge #{rows.first.billable_metric_code} (#{charge_id}): #{rows.size} differing leaf/leaves, see the CSV"
  end
end

def recurring_snapshots_audit_csv_rows(subscription, audit)
  audit.rows.map do |row|
    [
      subscription.id,
      subscription.external_id,
      row.charge_id,
      row.billable_metric_code,
      row.charge_filter_id,
      row.grouped_by.to_json,
      row.to_datetime.iso8601(6),
      row.watermark.iso8601(6),
      row.bounded,
      row.stored&.units&.to_s("F"),
      row.recomputed&.units&.to_d&.to_s("F"),
      row.stored&.events_count,
      row.recomputed&.events_count
    ]
  end
end

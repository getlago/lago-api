# frozen_string_literal: true

require "csv"
require_relative "../../task_prompt"

REALTIME_USAGE_CSV_HEADERS = %w[
  subscription_id
  external_subscription_id
  charge_id
  billable_metric_code
  charge_filter_id
  grouped_by
  served
  classification
  bucket_units
  events_units
  units_diff
  bucket_amount_cents
  events_amount_cents
  amount_cents_diff
  bucket_events_count
  events_events_count
  duplicate_events
].freeze

namespace :recipes do
  namespace :realtime_usage do
    desc "Compare the current usage served from the usage buckets with the one computed from the events store"
    task compare_usage: :environment do
      Rails.logger.level = Logger::Severity::ERROR

      puts "The realtime usage gate is forced open for the bucket run: the feature flag and the"
      puts "LAGO_REALTIME_USAGE_ENABLED kill switch are bypassed."
      puts "The stream and the events store collapse duplicates on different keys, so read the"
      puts "duplicate event count of each subscription before concluding on a mismatch."
      puts ""

      organization = TaskPrompt.ask_for_organization

      abort "A premium license is required to read the usage buckets." unless License.premium?
      abort "ClickHouse is not enabled on this deployment (LAGO_CLICKHOUSE_ENABLED)." unless Events::Stores::StoreFactory.supports_clickhouse?
      abort "The organization still reads the Postgres events store, the buckets cannot be compared." unless organization.clickhouse_events_store?

      subscriptions = realtime_usage_subscriptions(organization)
      abort "No subscription to compare." if subscriptions.empty?

      default_path = Rails.root.join("tmp", "realtime_usage_comparison_#{organization.id}_#{Time.current.to_i}.csv").to_s
      csv_path = TaskPrompt.ask("CSV output path [#{default_path}]: ")
      csv_path = default_path if csv_path.empty?

      puts ""
      puts "Comparing #{subscriptions.size} subscription(s)"

      csv_rows = []
      compared = 0
      failed = 0
      declined = 0
      mismatching = 0
      with_cutover_risk = 0
      eligible_charges = 0
      served_charges = 0

      subscriptions.each do |subscription|
        comparison = RealtimeUsage::CompareUsageService.call(subscription:)

        unless comparison.success?
          failed += 1
          puts "  Subscription #{subscription.id}: FAILED (#{comparison.error})"
          next
        end

        compared += 1
        eligible_charges += comparison.eligible_charges_count
        served_charges += comparison.served_charges_count
        declined += 1 if comparison.served_charges_count.zero?
        mismatching += 1 if comparison.differences.any?
        with_cutover_risk += 1 if comparison.cutover_risks.any?

        csv_rows.concat(realtime_usage_csv_rows(subscription, comparison))
        realtime_usage_print_comparison(subscription, comparison)
      end

      CSV.open(csv_path, "w") do |csv|
        csv << REALTIME_USAGE_CSV_HEADERS
        csv_rows.each { csv << it }
      end

      puts ""
      puts "Summary"
      puts "  subscriptions compared:      #{compared} (#{failed} failed)"
      puts "  charges served from buckets: #{served_charges}/#{eligible_charges} comparable"
      puts "  subscriptions declined:      #{declined} (nothing was served, nothing was compared)"
      puts "  subscriptions mismatching:   #{mismatching}"
      puts "  subscriptions at cutover risk (re-sent transaction ids): #{with_cutover_risk}"
      puts "  per-leaf CSV: #{csv_path}"
      puts ""
      puts(if served_charges.zero?
        "Nothing was served from the buckets: this run says nothing about parity."
      elsif mismatching.zero?
        "No mismatch over the charges actually served."
      else
        "Mismatches detected, investigate before enabling the organization."
      end)
    end
  end
end

def realtime_usage_subscriptions(organization)
  subscription_ids = TaskPrompt.ask_for_subscription_ids
  return Subscription.where(organization_id: organization.id, id: subscription_ids).to_a if subscription_ids.any?

  active_count = Subscription.active.where(organization_id: organization.id).count
  puts "Organization has #{active_count} active subscription(s)."
  sample_size = TaskPrompt.ask("Number of active subscriptions to sample [50]: ")
  sample_size = sample_size.empty? ? 50 : sample_size.to_i

  Subscription.active
    .where(organization_id: organization.id)
    .order(Arel.sql("RANDOM()"))
    .limit(sample_size)
    .to_a
end

# Rolled up to charge level: the leaf detail of every charge is in the CSV.
def realtime_usage_print_comparison(subscription, comparison)
  status = if comparison.served_charges_count.zero?
    "DECLINED: #{comparison.declined_reason}"
  elsif comparison.differences.any?
    "DIFF"
  else
    "OK"
  end
  recheck = comparison.rechecked ? " (rechecked)" : ""

  puts "  Subscription #{subscription.id} (#{subscription.external_id}): " \
       "#{comparison.served_charges_count}/#{comparison.eligible_charges_count} charges served, " \
       "#{comparison.duplicate_events_count} duplicate event(s), " \
       "#{comparison.differences.size} mismatching leaf/leaves [#{status}]#{recheck}"

  comparison.differences.group_by(&:charge_id).each do |charge_id, rows|
    puts "      charge #{rows.first.billable_metric_code} (#{charge_id}): #{rows.size} mismatching leaf/leaves, see the CSV"
  end

  comparison.cutover_risks.group_by(&:charge_id).each do |charge_id, rows|
    puts "      charge #{rows.first.billable_metric_code} (#{charge_id}): #{rows.size} leaf/leaves moved by a re-sent transaction id (cutover risk)"
  end
end

def realtime_usage_csv_rows(subscription, comparison)
  comparison.rows.map do |row|
    [
      subscription.id,
      subscription.external_id,
      row.charge_id,
      row.billable_metric_code,
      row.charge_filter_id,
      row.grouped_by.to_json,
      row.served,
      row.classification,
      row.bucket_units.to_s("F"),
      row.events_units.to_s("F"),
      row.units_diff.to_s("F"),
      row.bucket_amount_cents,
      row.events_amount_cents,
      row.amount_cents_diff,
      row.bucket_events_count,
      row.events_events_count,
      comparison.duplicate_events_count
    ]
  end
end

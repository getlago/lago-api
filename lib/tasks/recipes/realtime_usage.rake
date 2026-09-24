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
  classification
  bucket_units
  events_units
  units_diff
  bucket_amount_cents
  events_amount_cents
  amount_cents_diff
  bucket_events_count
  events_events_count
  events_count_diff
  duplicate_events
].freeze

namespace :recipes do
  namespace :realtime_usage do
    desc "Report whether an organization can be served current usage from the ClickHouse usage buckets"
    task check_eligibility: :environment do
      Rails.logger.level = Logger::Severity::ERROR

      organization = TaskPrompt.ask_for_organization

      puts ""
      puts "Gates that are not switches"
      realtime_usage_print_gate("premium license", License.premium?)
      realtime_usage_print_gate("clickhouse enabled on the deployment", Events::Stores::StoreFactory.supports_clickhouse?)
      realtime_usage_print_gate("organization reads the clickhouse events store", organization.clickhouse_events_store?)

      puts ""
      puts "Switches, as they stand today"
      kill_switch = ActiveModel::Type::Boolean.new.cast(ENV["LAGO_REALTIME_USAGE_ENABLED"])
      puts "  LAGO_REALTIME_USAGE_ENABLED: #{kill_switch ? "on" : "off"}"
      puts "  realtime_usage feature flag:  #{organization.feature_flag_enabled?(:realtime_usage) ? "on" : "off"}"

      subscriptions = organization.subscriptions.active.includes(plan: {charges: :billable_metric}).to_a
      if subscriptions.empty?
        puts ""
        puts "No active subscription: nothing to serve, and nothing this task can say about coverage."
        next
      end

      report = realtime_usage_eligibility_report(subscriptions)

      puts ""
      puts "Coverage over #{subscriptions.size} active subscription(s)"
      puts "  fully served:   #{report[:fully_served]}"
      puts "  partly served:  #{report[:partly_served]}"
      puts "  not served:     #{report[:not_served]}"
      puts "  no charge at all: #{report[:without_charges]}" if report[:without_charges].positive?
      puts "  distinct charges served: #{report[:served_charges]}/#{report[:total_charges]}"

      if report[:blockers].any?
        puts ""
        puts "What is keeping the rest on the events store, worst first"
        report[:blockers].each do |reason, entry|
          puts "  #{reason}: #{entry[:charge_ids].size} charge(s), #{entry[:subscriptions].size} subscription(s)"
          entry[:labels].first(10).each { puts "    #{it}" }
          puts "    … and #{entry[:labels].size - 10} more" if entry[:labels].size > 10
        end
      end

      puts ""
      puts(realtime_usage_verdict(organization, report, kill_switch))
    end

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
      puts "  of which a re-sent transaction id may explain: #{with_cutover_risk}"
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

  comparison.differences.select(&:mismatch?).group_by(&:charge_id).each do |charge_id, rows|
    puts "      charge #{rows.first.billable_metric_code} (#{charge_id}): #{rows.size} mismatching leaf/leaves, see the CSV"
  end

  comparison.cutover_risks.group_by(&:charge_id).each do |charge_id, rows|
    puts "      charge #{rows.first.billable_metric_code} (#{charge_id}): #{rows.size} differing leaf/leaves the window holds duplicates for (cutover risk)"
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
      row.classification,
      row.bucket_units.to_s("F"),
      row.events_units.to_s("F"),
      row.units_diff.to_s("F"),
      row.bucket_amount_cents,
      row.events_amount_cents,
      row.amount_cents_diff,
      row.bucket_events_count,
      row.events_events_count,
      row.events_count_diff,
      comparison.duplicate_events_count
    ]
  end
end

def realtime_usage_print_gate(label, ok)
  puts "  [#{ok ? "x" : " "}] #{label}"
end

# Charges are shared by every subscription on a plan, so coverage is counted twice: once over
# distinct charges, which says what to fix, and once over subscriptions, which says how much of
# the organization the fix is worth.
def realtime_usage_eligibility_report(subscriptions)
  fully_served = 0
  partly_served = 0
  not_served = 0
  without_charges = 0
  served_charge_ids = Set.new
  charge_ids = Set.new
  blockers = Hash.new { |hash, key| hash[key] = {charge_ids: Set.new, labels: Set.new, subscriptions: Set.new} }

  subscriptions.each do |subscription|
    charges = subscription.plan.charges
    if charges.empty?
      without_charges += 1
      next
    end

    served = 0
    charges.each do |charge|
      charge_ids << charge.id
      reason = realtime_usage_charge_blocker(charge)

      if reason.nil?
        served += 1
        served_charge_ids << charge.id
        next
      end

      blocker = blockers[reason]
      blocker[:charge_ids] << charge.id
      blocker[:labels] << realtime_usage_charge_label(charge)
      blocker[:subscriptions] << subscription.id
    end

    case served
    when charges.size then fully_served += 1
    when 0 then not_served += 1
    else partly_served += 1
    end
  end

  {
    fully_served:,
    partly_served:,
    not_served:,
    without_charges:,
    served_charges: served_charge_ids.size,
    total_charges: charge_ids.size,
    blockers: blockers.sort_by { |_reason, entry| -entry[:subscriptions].size }
  }
end

# The presentation breakdown is not in RealtimeUsage.unsupported_reason because it depends on the
# caller: one that suppresses the breakdown, like the wallet refresh, still serves the charge.
# Ordinary current usage asks for it, so the rollout decision has to count it as delegated.
def realtime_usage_charge_blocker(charge)
  reason = RealtimeUsage.unsupported_reason(charge)
  return reason if reason

  "presentation_breakdown" if charge.presentation_group_keys_values.present?
end

def realtime_usage_charge_label(charge)
  billable_metric = charge.billable_metric

  "#{billable_metric.code} (#{billable_metric.aggregation_type}, #{charge.charge_model}) on plan #{charge.plan.code}"
end

def realtime_usage_verdict(organization, report, kill_switch)
  unless License.premium? && Events::Stores::StoreFactory.supports_clickhouse?
    return "Not a candidate: the deployment itself cannot serve the buckets."
  end

  unless organization.clickhouse_events_store?
    return "Not a candidate: the organization reads the Postgres events store, so the buckets and " \
           "the events would disagree. Migrate it to ClickHouse first."
  end

  if report[:served_charges].zero?
    return "Not worth enabling: no charge on an active subscription can be served from the buckets."
  end

  served = "#{report[:served_charges]}/#{report[:total_charges]} charges, " \
           "#{report[:fully_served]} fully served subscription(s)"

  flag_enabled = organization.feature_flag_enabled?(:realtime_usage)

  next_step = if kill_switch && flag_enabled
    "Already serving: both switches are on. Re-run recipes:realtime_usage:compare_usage to confirm parity."
  elsif kill_switch
    "Next: run recipes:realtime_usage:compare_usage for this organization, then enable the realtime_usage flag."
  elsif flag_enabled
    "Next: the realtime_usage flag is on but LAGO_REALTIME_USAGE_ENABLED is off, so nothing is served. " \
      "Run recipes:realtime_usage:compare_usage, then turn the kill switch on."
  else
    "Next: run recipes:realtime_usage:compare_usage, then enable LAGO_REALTIME_USAGE_ENABLED and the " \
      "realtime_usage flag."
  end

  "Candidate: #{served}. #{next_step}"
end

# frozen_string_literal: true

require "csv"
require_relative "../../task_prompt"

# A row is a subscription's (charge, charge filter) leaf or a contract's (product, product filter) one
RECURRING_SNAPSHOTS_CSV_HEADERS = %w[
  owner_type
  owner_id
  external_id
  item_id
  billable_metric_code
  filter_id
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
  snapshot_presentation_breakdowns
  full_scan_presentation_breakdowns
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
  "owner_type",
  "owner_id",
  "external_id",
  "event_transaction_id",
  "event_timestamp",
  "item_id",
  "billable_metric_code",
  "filter_id",
  "grouped_by",
  "snapshot_read",
  *RECURRING_SNAPSHOTS_PAY_IN_ADVANCE_AGGREGATION_FIELDS.flat_map { ["snapshot_#{it}", "full_scan_#{it}"] }
].freeze

namespace :recipes do
  namespace :recurring_aggregation_snapshots do
    desc "Compare the current usage and the pay in advance aggregation of recurring charges and products read from the snapshots with the ones scanning the full history"
    task compare_usage: :environment do
      Rails.logger.level = Logger::Severity::ERROR

      puts "The persisted_recurring_values flag is forced on for the snapshot run and off for the"
      puts "full scan run, whatever it is set to for the organization. Nothing is persisted."
      puts ""

      organization = TaskPrompt.ask_for_organization

      subscriptions = TaskPrompt.ask_for_sampled_subscriptions(organization)
      contracts = recurring_snapshots_compared_contracts(organization)
      abort "No subscription or contract to compare." if subscriptions.empty? && contracts.empty?

      default_path = Rails.root.join("tmp", "recurring_snapshots_comparison_#{organization.id}_#{Time.current.to_i}.csv").to_s
      csv_path = TaskPrompt.ask("CSV output path [#{default_path}]: ")
      csv_path = default_path if csv_path.empty?
      pay_in_advance_csv_path = csv_path.sub(/(\.csv)?\z/, "_pay_in_advance.csv")

      puts ""
      puts "Comparing #{subscriptions.size} subscription(s)"
      puts "Comparing #{contracts.size} contract(s)" if contracts.any?

      csv_rows = []
      pay_in_advance_csv_rows = []
      pay_in_advance_charges = 0
      pay_in_advance_events = 0
      pay_in_advance_snapshot_buckets = 0
      compared = 0
      failed = 0
      pay_in_advance_failed = 0
      without_snapshot = 0
      mismatching = 0

      owners = subscriptions.map { [:subscription, it] } + contracts.map { [:contract, it] }
      owners.each do |owner_type, owner|
        usage_service = (owner_type == :contract) ? RecurringAggregationSnapshots::CompareContractUsageService : RecurringAggregationSnapshots::CompareUsageService
        comparison = usage_service.call(owner_type => owner)

        unless comparison.success?
          failed += 1
          puts "  #{owner_type.to_s.capitalize} #{owner.id}: FAILED (#{comparison.error})"
          next
        end

        csv_rows.concat(recurring_snapshots_csv_rows(owner_type, owner, comparison))
        recurring_snapshots_print_comparison(owner_type, owner, comparison)

        compared += 1
        pay_in_advance = RecurringAggregationSnapshots::ComparePayInAdvanceService.call(owner_type => owner)

        if pay_in_advance.success?
          pay_in_advance_charges += pay_in_advance.compared_items_count
          pay_in_advance_events += pay_in_advance.compared_events_count
          pay_in_advance_snapshot_buckets += pay_in_advance.rows.count(&:snapshot_read)
          pay_in_advance_csv_rows.concat(recurring_snapshots_pay_in_advance_csv_rows(owner_type, owner, pay_in_advance))
          recurring_snapshots_print_pay_in_advance_comparison(pay_in_advance)
        else
          pay_in_advance_failed += 1
          puts "      pay in advance: FAILED (#{pay_in_advance.error})"
        end

        pay_in_advance_rows = pay_in_advance.success? ? pay_in_advance.rows : []
        if pay_in_advance.success? && comparison.snapshot_items_count.zero? && pay_in_advance_rows.none?(&:snapshot_read)
          without_snapshot += 1
        end
        mismatching += 1 if comparison.differences.any? || pay_in_advance_rows.any?(&:different?)
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
      puts "Summary, over subscriptions and contracts"
      puts "  compared:                       #{compared} (#{failed} failed)"
      puts "  without snapshot:               #{without_snapshot} (full scan on both sides, nothing compared)"
      puts "  mismatching:                    #{mismatching}"
      puts "  pay in advance events replayed: #{pay_in_advance_events} (#{pay_in_advance_failed} failed)"
      puts "  pay in advance buckets read from a snapshot: #{pay_in_advance_snapshot_buckets}"
      puts "  per-leaf CSV: #{csv_path}"
      puts "  per-event pay in advance CSV: #{pay_in_advance_csv_path}"
      puts ""
      puts(if compared.zero?
        "Nothing could be compared."
      elsif mismatching.positive?
        "Mismatches detected, investigate before enabling the organization."
      elsif (failed + pay_in_advance_failed).positive?
        "No mismatch over the comparisons that ran, but #{failed + pay_in_advance_failed} failed: rerun them before enabling the organization."
      elsif compared == without_snapshot
        "No subscription or contract read a snapshot: this run says nothing about parity."
      elsif pay_in_advance_charges.positive? && pay_in_advance_snapshot_buckets.zero?
        "No mismatch over the items read from a snapshot, but no pay in advance bucket read one: this run says nothing about pay in advance parity."
      else
        "No mismatch over the items and events read from a snapshot."
      end)
    end
  end
end

# Contracts are asked only when the organization has active contracts with snapshots: one without
# snapshots compares nothing, and an ended one has no open segment to price
def recurring_snapshots_compared_contracts(organization)
  # Correlated on the contract, so the contract-led snapshot index serves it
  snapshots = ContractRecurringAggregationSnapshot.where("contract_recurring_aggregation_snapshots.contract_id = contracts.id")
  compared = organization.contracts.where(status: Contract::BILLABLE_STATUSES).where(snapshots.arel.exists)
  return [] unless compared.exists?

  input = TaskPrompt.ask("Contract IDs to compare (comma or space separated, leave blank to sample the organization, none to skip contracts): ")
  return [] if input.strip.casecmp?("none")

  contract_ids = input.split(/[\s,]+/).reject(&:empty?)

  if contract_ids.any?
    contracts = compared.where(id: contract_ids).to_a
    missing_ids = contract_ids - contracts.map(&:id)
    puts "Not found in the organization, not active or without snapshots, skipped: #{missing_ids.join(", ")}" if missing_ids.any?

    return contracts
  end

  puts "Organization has #{compared.count} active contract(s) with snapshots."
  sample_size = TaskPrompt.ask("Number of contracts to sample [50]: ")
  sample_size = sample_size.empty? ? 50 : Integer(sample_size, exception: false)
  abort "Invalid sample size: expected a positive integer." unless sample_size&.positive?

  compared.order(Arel.sql("RANDOM()")).limit(sample_size).to_a
end

def recurring_snapshots_print_comparison(owner_type, owner, comparison)
  items = (owner_type == :contract) ? "products" : "charges"
  status = if comparison.snapshot_items_count.zero?
    "NO SNAPSHOT"
  elsif comparison.differences.any?
    "DIFF"
  else
    "OK"
  end

  puts "  #{owner_type.to_s.capitalize} #{owner.id} (#{owner.external_id}): " \
       "#{comparison.snapshot_items_count}/#{comparison.compared_items_count} #{items} read from a snapshot, " \
       "#{comparison.differences.size} mismatching leaf/leaves [#{status}]"

  comparison.differences.group_by(&:item_id).each do |item_id, rows|
    puts "      #{items.singularize} #{rows.first.billable_metric_code} (#{item_id}): #{rows.size} mismatching leaf/leaves, see the CSV"
  end
end

def recurring_snapshots_csv_rows(owner_type, owner, comparison)
  comparison.rows.map do |row|
    [
      owner_type,
      owner.id,
      owner.external_id,
      row.item_id,
      row.billable_metric_code,
      row.filter_id,
      row.grouped_by.to_json,
      row.snapshot_read,
      recurring_snapshots_csv_value(row.snapshot.units),
      recurring_snapshots_csv_value(row.full_scan.units),
      recurring_snapshots_csv_value(row.snapshot.total_aggregated_units),
      recurring_snapshots_csv_value(row.full_scan.total_aggregated_units),
      row.snapshot.amount_cents,
      row.full_scan.amount_cents,
      row.snapshot.events_count,
      row.full_scan.events_count,
      recurring_snapshots_breakdowns_json(row.snapshot),
      recurring_snapshots_breakdowns_json(row.full_scan)
    ]
  end
end

def recurring_snapshots_breakdowns_json(totals)
  totals.presentation_breakdowns.map { |groups, units| {groups:, units: units.to_s("F")} }.to_json
end

def recurring_snapshots_print_pay_in_advance_comparison(comparison)
  return if comparison.compared_items_count.zero?

  puts "      pay in advance: #{comparison.compared_events_count} event(s) replayed, " \
       "#{comparison.rows.count(&:snapshot_read)} bucket(s) read from a snapshot, " \
       "#{comparison.differences.size} mismatching"

  comparison.differences.group_by(&:item_id).each do |item_id, rows|
    puts "      #{rows.first.billable_metric_code} (#{item_id}): #{rows.size} mismatching event bucket(s), see the CSV"
  end
end

def recurring_snapshots_pay_in_advance_csv_rows(owner_type, owner, comparison)
  comparison.rows.map do |row|
    [
      owner_type,
      owner.id,
      owner.external_id,
      row.event_transaction_id,
      row.event_timestamp.iso8601(3),
      row.item_id,
      row.billable_metric_code,
      row.filter_id,
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

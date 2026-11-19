# frozen_string_literal: true

require "csv"
require_relative "../../task_prompt"

# A row is a subscription's (charge, charge filter) leaf or a contract's (product, product filter) one
RECURRING_SNAPSHOTS_AUDIT_CSV_HEADERS = %w[
  owner_type
  owner_id
  external_id
  item_id
  filter_id
  grouped_by
  to_datetime
  snapshot_units
  fee_units
  snapshot_events_count
  fee_events_count
].freeze

namespace :recipes do
  namespace :recurring_aggregation_snapshots do
    desc "Compare the snapshots of each closed period with the fees of its invoice"
    task audit: :environment do
      Rails.logger.level = Logger::Severity::ERROR

      organization = TaskPrompt.ask_for_organization

      subscriptions = TaskPrompt.ask_for_sampled_subscriptions(organization)
      contracts = recurring_snapshots_audit_contracts(organization)
      abort "No subscription or contract to audit." if subscriptions.empty? && contracts.empty?

      default_path = Rails.root.join("tmp", "recurring_snapshots_audit_#{organization.id}_#{Time.current.to_i}.csv").to_s
      csv_path = TaskPrompt.ask("CSV output path [#{default_path}]: ")
      csv_path = default_path if csv_path.empty?

      puts ""
      puts "Auditing #{subscriptions.size} subscription(s)"
      puts "Auditing #{contracts.size} contract(s)" if contracts.any?

      totals = Hash.new(0)

      CSV.open(csv_path, "w") do |csv|
        csv << RECURRING_SNAPSHOTS_AUDIT_CSV_HEADERS

        subscriptions.each do |subscription|
          audit = RecurringAggregationSnapshots::AuditService.call!(subscription:)
          recurring_snapshots_audit_count(totals, audit)
          totals[:adjusted_rows] += audit.adjusted_rows.size
          totals[:periods_without_marker] += audit.periods_without_marker.size

          puts "  Subscription #{subscription.id} (#{subscription.external_id}): #{audit.rows.size} leaf/leaves, " \
               "#{audit.differences.size} differing, #{audit.adjusted_rows.size} adjusted, #{recurring_snapshots_audit_summary(audit)}, " \
               "#{audit.periods_without_marker.size} period(s) without marker"

          audit.differences.each do |row|
            csv << recurring_snapshots_audit_csv_row("subscription", subscription, row.charge_id, row.charge_filter_id, row)
          end
        end

        contracts.each do |contract|
          audit = RecurringAggregationSnapshots::ContractAuditService.call!(contract:)
          recurring_snapshots_audit_count(totals, audit)

          puts "  Contract #{contract.id} (#{contract.external_id}): #{audit.rows.size} leaf/leaves, " \
               "#{audit.differences.size} differing, #{recurring_snapshots_audit_summary(audit)}"

          audit.differences.each do |row|
            csv << recurring_snapshots_audit_csv_row("contract", contract, row.product_id, row.product_filter_id, row)
          end
        end
      end

      puts ""
      puts "Differing leaves: #{totals[:differences]}, adjusted leaves: #{totals[:adjusted_rows]}, " \
           "leaves explained by events ingested after the watermark: #{totals[:watermark_gap_rows]}, " \
           "periods without invoice: #{totals[:periods_without_invoice]}, periods without marker: #{totals[:periods_without_marker]}"
      puts "Differences: #{csv_path}"
    end
  end
end

# Asked only when the organization has contract snapshots: contract periods need no marker of their own
def recurring_snapshots_audit_contracts(organization)
  audited = organization.contracts.where(
    id: ContractRecurringAggregationSnapshot.where(organization_id: organization.id).select(:contract_id)
  )
  return [] unless audited.exists?

  contract_ids = TaskPrompt.ask_for_ids("Contract IDs to audit (comma or space separated, leave blank to sample the organization): ")
  return recurring_snapshots_audit_sampled_contracts(audited) if contract_ids.empty?

  contracts = audited.where(id: contract_ids).to_a
  missing_ids = contract_ids - contracts.map(&:id)
  puts "Not found in the organization or without snapshots, skipped: #{missing_ids.join(", ")}" if missing_ids.any?

  contracts
end

def recurring_snapshots_audit_sampled_contracts(audited)
  puts "Organization has #{audited.count} contract(s) with snapshots."
  sample_size = TaskPrompt.ask("Number of contracts to sample [50]: ")
  sample_size = sample_size.empty? ? 50 : Integer(sample_size, exception: false)
  abort "Invalid sample size: expected a positive integer." unless sample_size&.positive?

  audited.order(Arel.sql("RANDOM()")).limit(sample_size).to_a
end

def recurring_snapshots_audit_count(totals, audit)
  %i[differences watermark_gap_rows periods_without_invoice].each { totals[it] += audit.public_send(it).size }
end

def recurring_snapshots_audit_summary(audit)
  "#{audit.watermark_gap_rows.size} explained by events ingested after the watermark, " \
    "#{audit.periods_without_invoice.size} period(s) without invoice"
end

def recurring_snapshots_audit_csv_row(owner_type, owner, item_id, filter_id, row)
  [
    owner_type,
    owner.id,
    owner.external_id,
    item_id,
    filter_id,
    row.grouped_by.to_json,
    row.to_datetime.iso8601(6),
    row.snapshot_units.to_d.to_s("F"),
    row.fee_units.to_d.to_s("F"),
    row.snapshot_events_count,
    row.fee_events_count
  ]
end

# frozen_string_literal: true

require "csv"
require_relative "../../task_prompt"

RECURRING_SNAPSHOTS_AUDIT_CSV_HEADERS = %w[
  subscription_id
  external_subscription_id
  charge_id
  charge_filter_id
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
      abort "No subscription to audit." if subscriptions.empty?

      default_path = Rails.root.join("tmp", "recurring_snapshots_audit_#{organization.id}_#{Time.current.to_i}.csv").to_s
      csv_path = TaskPrompt.ask("CSV output path [#{default_path}]: ")
      csv_path = default_path if csv_path.empty?

      puts ""
      puts "Auditing #{subscriptions.size} subscription(s)"

      differences = 0
      periods_without_invoice = 0

      CSV.open(csv_path, "w") do |csv|
        csv << RECURRING_SNAPSHOTS_AUDIT_CSV_HEADERS

        subscriptions.each do |subscription|
          audit = RecurringAggregationSnapshots::AuditService.call!(subscription:)
          differences += audit.differences.size
          periods_without_invoice += audit.periods_without_invoice.size

          puts "  Subscription #{subscription.id} (#{subscription.external_id}): " \
               "#{audit.rows.size} leaf/leaves, #{audit.differences.size} differing, " \
               "#{audit.periods_without_invoice.size} period(s) without invoice"

          audit.differences.each do |row|
            csv << [
              subscription.id,
              subscription.external_id,
              row.charge_id,
              row.charge_filter_id,
              row.grouped_by.to_json,
              row.to_datetime.iso8601(6),
              row.snapshot_units.to_d.to_s("F"),
              row.fee_units.to_d.to_s("F"),
              row.snapshot_events_count,
              row.fee_events_count
            ]
          end
        end
      end

      puts ""
      puts "Differing leaves: #{differences}, periods without invoice: #{periods_without_invoice}"
      puts "Differences: #{csv_path}"
      puts "A sum snapshot stops at its watermark: an event ingested between the watermark and the invoice differs too."
    end
  end
end

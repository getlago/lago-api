# frozen_string_literal: true

namespace :multi_customer_connections do
  desc "Backfill connection codes + category + mark existing connection is_default (ING-452). " \
    "Usage: rake multi_customer_connections:backfill_connection_codes[organization_id] " \
    "(omit organization_id to run for every organization). DRY_RUN=false to persist, BATCH_SIZE to tune."
  task :backfill_connection_codes, [:organization_id] => :environment do |_task, args|
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    batch_size = (ENV["BATCH_SIZE"] || 1000).to_i
    abort "BATCH_SIZE must be positive" if batch_size <= 0

    mode = dry_run ? "DRY RUN" : "LIVE"
    scope = args[:organization_id] ? Organization.where(id: args[:organization_id]) : Organization.all

    totals = Hash.new(0)
    org_count = 0

    puts "Starting connection-codes backfill [#{mode}] (batch_size: #{batch_size})..."

    scope.find_each do |organization|
      org_count += 1
      summary = MultiCustomerConnections::BackfillConnectionCodesService.call!(
        organization:, dry_run:, batch_size:
      ).summary

      summary.each { |key, value| totals[key] += value }
      next if summary.values.all?(&:zero?)

      puts "  org=#{organization.id} #{summary.inspect}"
    end

    puts "Done [#{mode}]. Organizations processed: #{org_count}."
    puts "  Totals: #{totals.inspect}"
    if totals[:payment_default_conflicts].positive? || totals[:integration_default_conflicts].positive?
      puts "  ⚠️  Conflicts found (more than one connection in a category) — resolve manually; no default was set for those."
    end
  end
end

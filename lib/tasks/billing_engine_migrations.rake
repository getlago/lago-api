# frozen_string_literal: true

namespace :billing_engine_migrations do
  desc "Copy the active subscriptions of a shadowing organization to its shadow organization"
  task :backfill_subscriptions, [:organization_id] => :environment do |_task, args|
    organization_id = args[:organization_id]
    abort "Missing organization_id argument\n\nUsage: rake billing_engine_migrations:backfill_subscriptions[organization_id]" if organization_id.blank?

    migration = BillingEngineMigration.find_by(organization_id:)
    abort "No billing engine migration for organization #{organization_id}" unless migration
    abort "Billing engine migration #{migration.id} is #{migration.status}, not shadowing" unless migration.shadowing?

    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    mode = dry_run ? "DRY RUN" : "LIVE"
    copied = 0
    skipped = 0

    puts "Starting subscriptions backfill [#{mode}] for organization #{organization_id}..."

    migration.organization.subscriptions
      .active
      .joins(:plan)
      .where(plans: {code: migration.plan_mapping.keys})
      .preload(:plan)
      .find_each do |subscription|
        if subscription.plan.parent_id.present?
          skipped += 1
          puts "  [DRY RUN] would skip subscription #{subscription.external_id} (plan_override_not_supported)" if dry_run
          next
        end

        copied += 1

        if dry_run
          puts "  [DRY RUN] would copy subscription #{subscription.external_id}"
        else
          BillingEngineMigrations::CopySubscriptionJob.perform_later(migration, subscription)
        end
      end

    puts "#{dry_run ? "Would enqueue" : "Enqueued"} #{copied} subscription(s), skipped #{skipped} (plan_override_not_supported) [#{mode}]"
  end

  desc "Copy the taxes, billing entities and billable metrics of a shadowing organization to its shadow organization"
  task :copy_setup, [:organization_id] => :environment do |_task, args|
    organization_id = args[:organization_id]
    abort "Missing organization_id argument\n\nUsage: rake billing_engine_migrations:copy_setup[organization_id]" if organization_id.blank?

    migration = BillingEngineMigration.find_by(organization_id:)
    abort "No billing engine migration for organization #{organization_id}" unless migration
    abort "Billing engine migration #{migration.id} is #{migration.status}, not shadowing" unless migration.shadowing?

    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    mode = dry_run ? "DRY RUN" : "LIVE"

    puts "Starting setup copy [#{mode}] for organization #{organization_id}..."

    records = BillingEngineMigrations::CopySetupService.call!(migration:, dry_run:).records
    records.each do |record|
      line = "  [#{mode}] #{record.resource} #{record.code}: #{record.outcome}"
      line += " (#{record.error.message})" if record.error
      puts line
    end

    counts = records.map(&:outcome).tally
    puts "Done [#{mode}]: #{counts.map { |outcome, count| "#{count} #{outcome}" }.join(", ").presence || "nothing to copy"}"
    abort "#{counts[:failed]} record(s) failed" if counts[:failed]
  end
end

# frozen_string_literal: true

class BillingEngineSubscriptionsBackfill
  BATCH_SIZE = 1_000

  def initialize(migration:, dry_run:)
    @migration = migration
    @dry_run = dry_run
    @enqueued = 0
    @skipped = Hash.new(0)
  end

  def run
    puts "Starting subscriptions backfill [#{mode}] for organization #{migration.organization_id}..."

    candidates.find_in_batches(batch_size: BATCH_SIZE) { |subscriptions| process(subscriptions) }

    puts "#{dry_run ? "Would enqueue" : "Enqueued"} #{enqueued} subscription(s), " \
      "skipped #{skipped.values.sum}#{skipped_breakdown} [#{mode}]"
  end

  private

  attr_reader :migration, :dry_run, :enqueued, :skipped

  def mode
    dry_run ? "DRY RUN" : "LIVE"
  end

  def candidates
    migration.organization.subscriptions
      .active
      .joins(:plan)
      .where(plans: {code: migration.plan_mapping.keys})
      .preload(:plan)
  end

  def process(subscriptions)
    copied_external_ids = live_contract_external_ids(subscriptions)

    subscriptions.each do |subscription|
      reason = skip_reason(subscription, copied_external_ids)
      reason ? skip(subscription, reason) : enqueue(subscription)
    end
  end

  def live_contract_external_ids(subscriptions)
    migration.shadow_organization.contracts.live
      .where(external_id: subscriptions.map(&:external_id))
      .pluck(:external_id)
      .to_set
  end

  def skip_reason(subscription, copied_external_ids)
    if subscription.plan.parent_id.present?
      "plan_override_not_supported"
    elsif subscription.ending_at&.past?
      "already_ended"
    elsif copied_external_ids.include?(subscription.external_id)
      "already_copied"
    end
  end

  def skip(subscription, reason)
    skipped[reason] += 1
    puts "  [#{mode}] #{dry_run ? "would skip" : "skipped"} subscription #{subscription.external_id} (#{reason})"
  end

  def enqueue(subscription)
    @enqueued += 1
    BillingEngineMigrations::CopySubscriptionJob.perform_later(migration, subscription) unless dry_run
    puts "  [#{mode}] #{dry_run ? "would copy" : "enqueued"} subscription #{subscription.external_id}"
  end

  def skipped_breakdown
    if skipped.empty?
      ""
    else
      " (#{skipped.sort.map { |reason, count| "#{reason}: #{count}" }.join(", ")})"
    end
  end
end

namespace :billing_engine_migrations do
  desc "Copy the active subscriptions of a shadowing organization to its shadow organization"
  task :backfill_subscriptions, [:organization_id] => :environment do |_task, args|
    organization_id = args[:organization_id]
    abort "Missing organization_id argument\n\nUsage: rake billing_engine_migrations:backfill_subscriptions[organization_id]" if organization_id.blank?

    migration = BillingEngineMigration.find_by(organization_id:)
    abort "No billing engine migration for organization #{organization_id}" unless migration
    abort "Billing engine migration #{migration.id} is #{migration.status}, not shadowing" unless migration.shadowing?

    BillingEngineSubscriptionsBackfill.new(migration:, dry_run: ENV.fetch("DRY_RUN", "true") != "false").run
  end
end

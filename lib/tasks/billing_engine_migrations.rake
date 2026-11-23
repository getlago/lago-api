# frozen_string_literal: true

class BillingEngineSubscriptionsBackfill
  CUSTOMER_BATCH_SIZE = 1_000

  def initialize(migration:, dry_run:, customers_per_minute:, customer_limit: nil)
    @migration = migration
    @dry_run = dry_run
    @customers_per_minute = customers_per_minute
    @customer_limit = customer_limit
    @enqueued_customers = 0
    @enqueued_subscriptions = 0
    @skipped = Hash.new(0)
  end

  def run
    puts "Starting subscriptions backfill [#{mode}] for organization #{migration.organization_id} " \
      "(#{customers_per_minute} customer(s) per minute#{", at most #{customer_limit}" if customer_limit})..."

    each_customer_batch do |customer_ids|
      process(candidates.where(customer_id: customer_ids).preload(:plan).to_a)
    end

    puts summary
    puts "Stopped at #{customer_limit} customer(s): run the task again once these jobs have run" if customer_limit_reached?
  end

  private

  attr_reader :migration, :dry_run, :customers_per_minute, :customer_limit,
    :enqueued_customers, :enqueued_subscriptions, :skipped

  def mode
    dry_run ? "DRY RUN" : "LIVE"
  end

  def candidates
    migration.organization.subscriptions
      .active
      .joins(:plan)
      .where(plans: {code: migration.plan_mapping.keys})
  end

  def each_customer_batch
    last_customer_id = nil

    until customer_limit_reached?
      customer_ids = customer_ids_after(last_customer_id)
      break if customer_ids.empty?

      yield customer_ids
      last_customer_id = customer_ids.last
    end
  end

  def customer_ids_after(customer_id)
    scope = candidates.distinct.order(:customer_id).limit(CUSTOMER_BATCH_SIZE)
    scope = scope.where(Subscription.arel_table[:customer_id].gt(customer_id)) if customer_id
    scope.pluck(:customer_id)
  end

  def process(subscriptions)
    codes = live_contract_codes(subscriptions)

    subscriptions.group_by(&:customer_id).each_value do |customer_subscriptions|
      break if customer_limit_reached?

      to_copy = customer_subscriptions.reject { |subscription| skipped?(subscription, codes) }
      enqueue(to_copy) if to_copy.any?
    end
  end

  def live_contract_codes(subscriptions)
    migration.shadow_organization.contracts.live
      .where(external_id: subscriptions.map(&:external_id))
      .pluck(:external_id, :code)
      .to_h
  end

  def skipped?(subscription, live_contract_codes)
    reason = skip_reason(subscription, live_contract_codes[subscription.external_id])
    skip(subscription, reason) if reason
    reason.present?
  end

  def skip_reason(subscription, live_contract_code)
    if subscription.plan.parent_id.present?
      "plan_override_not_supported"
    elsif subscription.ending_at&.past?
      "already_ended"
    elsif live_contract_code == subscription.id
      "already_copied"
    elsif live_contract_code
      "external_id_taken_by_other_subscription"
    end
  end

  def skip(subscription, reason)
    skipped[reason] += 1
    puts "  [#{mode}] #{dry_run ? "would skip" : "skipped"} subscription #{subscription.external_id} (#{reason})"
  end

  def enqueue(subscriptions)
    unless dry_run
      BillingEngineMigrations::CopyCustomerSubscriptionsJob
        .set(wait: (enqueued_customers / customers_per_minute).minutes)
        .perform_later(migration, subscriptions.map(&:id))
    end

    @enqueued_customers += 1
    @enqueued_subscriptions += subscriptions.size
    subscriptions.each do |subscription|
      puts "  [#{mode}] #{dry_run ? "would copy" : "enqueued"} subscription #{subscription.external_id}"
    end
  end

  def customer_limit_reached?
    customer_limit.present? && enqueued_customers >= customer_limit
  end

  def summary
    "#{dry_run ? "Would enqueue" : "Enqueued"} #{enqueued_subscriptions} subscription(s) " \
      "of #{enqueued_customers} customer(s) over #{spread_minutes} minute(s), " \
      "skipped #{skipped.values.sum}#{skipped_breakdown} [#{mode}]"
  end

  def spread_minutes
    enqueued_customers.fdiv(customers_per_minute).ceil
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
    unless migration.shadow_organization_isolated?
      abort "Shadow organization #{migration.shadow_organization_id} has webhook endpoints, invoice emails or a dunning campaign"
    end

    customers_per_minute = Integer(ENV.fetch("CUSTOMERS_PER_MINUTE", "60"), exception: false)
    abort "CUSTOMERS_PER_MINUTE must be a positive integer" unless customers_per_minute&.positive?

    customer_limit = ENV["LIMIT"].presence && Integer(ENV["LIMIT"], exception: false)
    abort "LIMIT must be a positive integer" if ENV["LIMIT"].present? && !customer_limit&.positive?

    BillingEngineSubscriptionsBackfill.new(
      migration:,
      dry_run: ENV.fetch("DRY_RUN", "true") != "false",
      customers_per_minute:,
      customer_limit:
    ).run
  end
end

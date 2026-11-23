# frozen_string_literal: true

class BillingEngineSubscriptionsBackfill
  CUSTOMER_BATCH_SIZE = 1_000

  def initialize(migration:, dry_run:, customers_per_minute:, customer_limit: nil, after_customer_id: nil)
    @migration = migration
    @dry_run = dry_run
    @customers_per_minute = customers_per_minute
    @customer_limit = customer_limit
    @after_customer_id = after_customer_id
    @last_customer_id = nil
    @enqueued_customers = 0
    @enqueued_subscriptions = 0
    @skipped = Hash.new(0)
  end

  def run
    puts "Starting subscriptions backfill [#{mode}] for organization #{migration.organization_id} " \
      "(#{customers_per_minute} customer(s) per minute#{", at most #{customer_limit}" if customer_limit})..."

    each_customer_batch do |customer_ids|
      process(candidates.where(customer_id: customer_ids).order(:customer_id, :started_at, :id).preload(:plan).to_a)
    end

    puts summary
    return unless customer_limit_reached?

    puts "Stopped at #{customer_limit} customer(s): once these jobs have run, run the task again with " \
      "AFTER_CUSTOMER_ID=#{last_customer_id}"
  end

  private

  attr_reader :migration, :dry_run, :customers_per_minute, :customer_limit, :after_customer_id,
    :enqueued_customers, :enqueued_subscriptions, :skipped, :last_customer_id

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
    customer_ids_to_process.each_slice(CUSTOMER_BATCH_SIZE) do |customer_ids|
      break if customer_limit_reached?

      yield customer_ids
    end
  end

  def customer_ids_to_process
    scope = candidates.distinct.order(:customer_id)
    scope = scope.where(Subscription.arel_table[:customer_id].gt(after_customer_id)) if after_customer_id
    scope.pluck(:customer_id)
  end

  def process(subscriptions)
    contracts = shadow_contracts(subscriptions)

    subscriptions.group_by(&:customer_id).each do |customer_id, customer_subscriptions|
      break if customer_limit_reached?

      to_copy = customer_subscriptions.reject { |subscription| skipped?(subscription, contracts) }
      enqueue(to_copy) if to_copy.any?
      @last_customer_id = customer_id
    end
  end

  def shadow_contracts(subscriptions)
    migration.shadow_organization.contracts
      .where(external_id: subscriptions.map(&:external_id))
      .pluck(:external_id, :code, :status)
      .group_by(&:first)
  end

  def skipped?(subscription, shadow_contracts)
    reason = skip_reason(subscription, shadow_contracts.fetch(subscription.external_id, []))
    skip(subscription, reason) if reason
    reason.present?
  end

  def skip_reason(subscription, contracts)
    live_code = contracts.find { |_, _, status| Contract::LIVE_STATUSES.include?(status) }&.second

    if subscription.plan.parent_id.present?
      "plan_override_not_supported"
    elsif subscription.ending_at&.past?
      "already_ended"
    elsif live_code == subscription.id
      "already_copied"
    elsif live_code
      "external_id_taken_by_other_subscription"
    elsif contracts.any? { |_, code, _| code == subscription.id }
      "shadow_contract_ended"
    end
  end

  def skip(subscription, reason)
    skipped[reason] += 1
    puts "  [#{mode}] #{dry_run ? "would skip" : "skipped"} subscription #{subscription.external_id} (#{reason})"
  end

  def enqueue(subscriptions)
    unless dry_run
      BillingEngineMigrations::CopyCustomerSubscriptionsJob
        .set(wait: (enqueued_customers * 60.0 / customers_per_minute).seconds)
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

class BillingEnginePlanEntitlementsCopy
  DONE = {"create" => "created", "update" => "updated", "remove" => "removed"}.freeze

  def initialize(migration:, dry_run:)
    @migration = migration
    @dry_run = dry_run
  end

  def run
    puts "Starting plan entitlements copy [#{mode}] for organization #{migration.organization_id}..."

    ActiveRecord::Base.transaction(requires_new: true) do
      report(BillingEngineMigrations::CopyEntitlementsService.call!(migration:))
      raise ActiveRecord::Rollback if dry_run
    end
  end

  private

  attr_reader :migration, :dry_run

  def mode
    dry_run ? "DRY RUN" : "LIVE"
  end

  def report(result)
    list("create", "feature", result.created_features)
    list("create", "privilege", result.created_privileges)
    result.catalog_plans.each { |code, plan_result| report_catalog_plan(code, plan_result) }
    result.missing_plan_codes.each { puts "  [#{mode}] skipped plan #{it} (plan_not_found)" }
    result.missing_catalog_plan_codes.each { puts "  [#{mode}] skipped catalog plan #{it} (catalog_plan_not_found)" }
    result.conflicting_catalog_plan_codes.each do
      puts "  [#{mode}] skipped catalog plan #{it} (mapped_plans_have_different_entitlements)"
    end
    puts summary(result)
  end

  def report_catalog_plan(code, plan_result)
    list("create", "entitlement", plan_result.created_entitlements, code)
    list("remove", "entitlement", plan_result.removed_entitlements, code)
    list("create", "value", plan_result.created_values, code)
    list("update", "value", plan_result.updated_values, code)
    list("remove", "value", plan_result.removed_values, code)
  end

  def list(action, record, codes, catalog_plan_code = nil)
    on_plan = " on catalog plan #{catalog_plan_code}" if catalog_plan_code
    codes.each { puts "  [#{mode}] #{verb(action)} #{record} #{it}#{on_plan}" }
  end

  def verb(action)
    dry_run ? "would #{action}" : DONE.fetch(action)
  end

  def summary(result)
    skipped = result.missing_plan_codes + result.missing_catalog_plan_codes + result.conflicting_catalog_plan_codes

    "Features: #{result.created_features.size} created. Privileges: #{result.created_privileges.size} created. " \
      "Catalog plans: #{result.catalog_plans.size} synced. Mappings skipped: #{skipped.size}. " \
      "Entitlements: #{plan_count(result, :created_entitlements)} created, #{plan_count(result, :removed_entitlements)} removed. " \
      "Values: #{plan_count(result, :created_values)} created, #{plan_count(result, :updated_values)} updated, " \
      "#{plan_count(result, :removed_values)} removed. [#{mode}]"
  end

  def plan_count(result, field)
    result.catalog_plans.values.sum { it.public_send(field).size }
  end
end

module BillingEngineMigrationTask
  def self.shadowing_migration!(task_name, organization_id)
    if organization_id.blank?
      abort "Missing organization_id argument\n\nUsage: rake billing_engine_migrations:#{task_name}[organization_id]"
    end

    migration = BillingEngineMigration.find_by(organization_id:)
    abort "No billing engine migration for organization #{organization_id}" unless migration
    abort "Billing engine migration #{migration.id} is #{migration.status}, not shadowing" unless migration.shadowing?

    migration
  end
end

namespace :billing_engine_migrations do
  desc "Copy the active subscriptions of a shadowing organization to its shadow organization"
  task :backfill_subscriptions, [:organization_id] => :environment do |_task, args|
    migration = BillingEngineMigrationTask.shadowing_migration!("backfill_subscriptions", args[:organization_id])
    unless migration.shadow_organization_isolated?
      abort "Shadow organization #{migration.shadow_organization_id} has webhook endpoints, invoice emails or a dunning campaign"
    end

    customers_per_minute = Integer(ENV.fetch("CUSTOMERS_PER_MINUTE", "60"), exception: false)
    abort "CUSTOMERS_PER_MINUTE must be a positive integer" unless customers_per_minute&.positive?

    customer_limit = ENV["LIMIT"].presence && Integer(ENV["LIMIT"], exception: false)
    abort "LIMIT must be a positive integer" if ENV["LIMIT"].present? && !customer_limit&.positive?

    after_customer_id = ENV["AFTER_CUSTOMER_ID"].presence
    abort "AFTER_CUSTOMER_ID must be a customer id" if after_customer_id && !Regex::UUID.match?(after_customer_id)

    BillingEngineSubscriptionsBackfill.new(
      migration:,
      dry_run: ENV.fetch("DRY_RUN", "true") != "false",
      customers_per_minute:,
      customer_limit:,
      after_customer_id:
    ).run
  end

  desc "Copy the features, privileges and plan entitlements of a shadowing organization to its shadow organization"
  task :copy_plan_entitlements, [:organization_id] => :environment do |_task, args|
    migration = BillingEngineMigrationTask.shadowing_migration!("copy_plan_entitlements", args[:organization_id])

    BillingEnginePlanEntitlementsCopy.new(migration:, dry_run: ENV.fetch("DRY_RUN", "true") != "false").run
  rescue BaseService::FailedResult => e
    abort "Plan entitlements copy failed: #{e.message}"
  end
end

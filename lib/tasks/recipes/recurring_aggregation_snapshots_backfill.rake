# frozen_string_literal: true

require "sidekiq/api"
require_relative "../../task_prompt"

RECURRING_SNAPSHOTS_BACKFILL_POLL_INTERVAL = 15

namespace :recipes do
  namespace :recurring_aggregation_snapshots do
    desc "Write with jobs the snapshots of the latest invoiced period of listed subscriptions and contracts, or of a whole organization"
    task backfill: :environment do
      Rails.logger.level = Logger::Severity::ERROR

      organization = TaskPrompt.ask_for_organization
      recurring_snapshots_backfill_warn_writes_off(organization)
      # Contracts are asked only when the organization has some, so organizations without contracts keep the
      # same prompts. Listing IDs at either prompt then limits the run to the listed ones.
      contracts = RecurringAggregationSnapshots::ContractBackfillService.backfillable_contracts(organization)
      with_contracts = contracts.exists?
      subscription_ids = if with_contracts
        TaskPrompt.ask_for_ids(
          "Subscription IDs to refill (comma or space separated, leave blank to fill every subscription of the organization, " \
          "or none when contract IDs are listed next): "
        )
      else
        TaskPrompt.ask_for_subscription_ids
      end

      subscriptions = RecurringAggregationSnapshots::BackfillService.backfillable_subscriptions(organization)
      if subscription_ids.any?
        subscriptions = subscriptions.where(id: subscription_ids)
        left_out_ids = subscription_ids - subscriptions.pluck(:id)
        recurring_snapshots_backfill_list("Skipped, not found or without a recurring sum charge or an invoiced period", left_out_ids)
      end

      contract_ids = []
      if with_contracts
        contract_ids = TaskPrompt.ask_for_ids(
          "Contract IDs to refill (comma or space separated, leave blank to fill every contract of the organization, " \
          "or none when subscription IDs were listed): "
        )
        if contract_ids.any?
          contracts = contracts.where(id: contract_ids)
          left_out_ids = contract_ids - contracts.pluck(:id)
          recurring_snapshots_backfill_list("Skipped, not found or without a recurring sum rate card or a closed period", left_out_ids)
        end
      end

      listed = subscription_ids.any? || contract_ids.any?
      subscriptions = subscriptions.none if listed && subscription_ids.empty?
      contracts = contracts.none if listed && contract_ids.empty?

      total = subscriptions.count
      contracts_total = contracts.count
      puts "#{total} active subscription(s) with a recurring sum charge and an invoiced period."
      puts "#{contracts_total} active contract(s) with a recurring sum rate card and a closed period." if contracts_total.positive?
      abort "No subscription or contract to backfill." if total.zero? && contracts_total.zero?

      TaskPrompt.confirm!("Enqueue a backfill job for each of them? (y/n): ")

      puts "Enqueuing, while #{RecurringAggregationSnapshots::BackfillJob.queue_name} holds less than " \
           "#{RecurringAggregationSnapshots::EnqueueBackfillService::MAX_QUEUE_SIZE} jobs..."
      started_at = Time.current
      enqueued = RecurringAggregationSnapshots::EnqueueBackfillService.call!(
        organization:, subscription_ids: (subscription_ids if listed), contract_ids: (contract_ids if listed)
      )
      enqueued_ids = enqueued.subscription_ids + enqueued.contract_ids
      puts "Enqueued #{enqueued_ids.size} job(s). Stopping this task leaves them running."

      # Progress comes from Sidekiq alone: the snapshots are read once, at the end. Sidekiq lists a busy
      # worker after a heartbeat of a few seconds, so the loop stops on the second poll with nothing pending.
      enqueued_set = enqueued_ids.to_set
      idle_polls = 0
      until idle_polls == 2
        Kernel.sleep RECURRING_SNAPSHOTS_BACKFILL_POLL_INTERVAL
        pending = recurring_snapshots_backfill_pending_jobs(enqueued_set)
        idle_polls = pending.zero? ? idle_polls + 1 : 0
        puts "  #{enqueued_set.size - pending}/#{enqueued_set.size} job(s) ran, #{pending} pending"
      end

      dead_ids = recurring_snapshots_backfill_dead_owner_ids(started_at)
      recurring_snapshots_backfill_report(
        "Subscriptions", total,
        enqueued_ids: enqueued.subscription_ids,
        not_enqueued_ids: subscriptions.where.not(id: enqueued.subscription_ids).pluck(:id),
        backfilled_ids: recurring_snapshots_backfilled_ids(subscriptions, started_at),
        dead_ids:
      )
      next if contracts_total.zero?

      recurring_snapshots_backfill_report(
        "Contracts", contracts_total,
        enqueued_ids: enqueued.contract_ids,
        not_enqueued_ids: contracts.where.not(id: enqueued.contract_ids).pluck(:id),
        backfilled_ids: recurring_snapshots_backfilled_contract_ids(contracts, started_at),
        dead_ids:
      )
    end
  end
end

def recurring_snapshots_backfill_warn_writes_off(organization)
  return if organization.feature_flag_enabled?(:recurring_aggregation_snapshots)

  puts "Warning: recurring_aggregation_snapshots is off, so no invoice will write the snapshots of later periods."
end

def recurring_snapshots_backfill_report(label, total, enqueued_ids:, not_enqueued_ids:, backfilled_ids:, dead_ids:)
  failed_ids = dead_ids & enqueued_ids
  unwritten_ids = enqueued_ids - backfilled_ids - failed_ids

  puts ""
  puts "#{label} backfilled: #{(backfilled_ids - failed_ids).size}/#{total}, failed: #{failed_ids.size}, " \
       "not enqueued: #{not_enqueued_ids.size}, nothing written: #{unwritten_ids.size}"
  recurring_snapshots_backfill_list("Failed, rerun them by listing them", failed_ids)
  recurring_snapshots_backfill_list("Not enqueued, a job of an earlier run still holds their lock (up to an hour)", not_enqueued_ids)
  recurring_snapshots_backfill_list("Nothing written, no snapshot to store (see Fees::ChargeService)", unwritten_ids)
end

# The subscriptions a job wrote a marker for since the task started
def recurring_snapshots_backfilled_ids(subscriptions, started_at)
  markers = RecurringAggregationSnapshot
    .where("recurring_aggregation_snapshots.subscription_id = subscriptions.id")
    .where(charge_filter_id: nil)
    .where(watermark: (started_at - RecurringAggregationSnapshot::WATERMARK_LAG).floor(3)..)

  subscriptions.where(markers.arel.exists).pluck(:id)
end

# The contracts a job wrote a snapshot for since the task started: every contract row marks its period
def recurring_snapshots_backfilled_contract_ids(contracts, started_at)
  snapshots = ContractRecurringAggregationSnapshot
    .where("contract_recurring_aggregation_snapshots.contract_id = contracts.id")
    .where(watermark: (started_at - RecurringAggregationSnapshot::WATERMARK_LAG).floor(3)..)

  contracts.where(snapshots.arel.exists).pluck(:id)
end

def recurring_snapshots_backfill_list(label, ids)
  return if ids.empty?

  puts "#{label}:"
  puts ids.join(",")
end

# The jobs of this run only: another organization can be backfilled at the same time.
# A job retried by `retry_on` waits in the scheduled set.
def recurring_snapshots_backfill_pending_jobs(owner_ids)
  entries = Sidekiq::Queue.new(RecurringAggregationSnapshots::BackfillJob.queue_name).to_a +
    Sidekiq::ScheduledSet.new.to_a +
    Sidekiq::Workers.new.map { |_process_id, _thread_id, work| work.job }

  recurring_snapshots_backfill_owner_ids(entries).count { owner_ids.include?(it) }
end

def recurring_snapshots_backfill_dead_owner_ids(started_at)
  recurring_snapshots_backfill_owner_ids(Sidekiq::DeadSet.new.select { it.at >= started_at }).uniq
end

# Sidekiq stores ActiveJob entries under its wrapper class: `display_class` reads the job's own name,
# and `display_args` the global id of its subscription or contract.
def recurring_snapshots_backfill_owner_ids(entries)
  entries
    .select { it.display_class == RecurringAggregationSnapshots::BackfillJob.name }
    .filter_map { GlobalID.parse(it.display_args.first)&.model_id }
end

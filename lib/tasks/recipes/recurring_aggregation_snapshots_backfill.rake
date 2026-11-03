# frozen_string_literal: true

require "sidekiq/api"
require_relative "../../task_prompt"

RECURRING_SNAPSHOTS_BACKFILL_POLL_INTERVAL = 15

namespace :recipes do
  namespace :recurring_aggregation_snapshots do
    desc "Write the snapshots of the latest invoiced period of existing subscriptions"
    task backfill: :environment do
      Rails.logger.level = Logger::Severity::ERROR

      organization = TaskPrompt.ask_for_organization
      recurring_snapshots_backfill_warn_writes_off(organization)

      subscriptions = TaskPrompt.ask_for_sampled_subscriptions(organization)
      abort "No subscription to backfill." if subscriptions.empty?

      puts ""
      puts "Backfilling #{subscriptions.size} subscription(s)"

      written = 0
      skipped = 0
      failed = 0
      failed_subscriptions = 0

      subscriptions.each do |subscription|
        label = "  Subscription #{subscription.id} (#{subscription.external_id})"
        backfill = RecurringAggregationSnapshots::BackfillService.call(subscription:)

        if backfill.failure?
          failed_subscriptions += 1
          puts "#{label}: not backfilled, #{backfill.error.code}"
        elsif backfill.invoice_subscription.nil?
          puts "#{label}: no invoiced period"
        else
          written += backfill.written_charges.size
          skipped += backfill.skipped_charges.size
          failed += backfill.failed_charges.size

          puts "#{label}: period ending #{backfill.invoice_subscription.charges_to_datetime.iso8601}, " \
               "#{backfill.written_charges.size} charge(s) written, #{backfill.skipped_charges.size} skipped, " \
               "#{backfill.failed_charges.size} failed#{" (#{backfill.failed_charges.map(&:id).join(", ")})" if backfill.failed_charges.any?}"
        end
      end

      puts ""
      puts "Charges written: #{written}, skipped: #{skipped}, failed: #{failed}, " \
           "subscriptions not backfilled: #{failed_subscriptions}"
    end

    desc "Enqueue a backfill job per active subscription of an organization, then follow them until they ran"
    task backfill_organization: :environment do
      Rails.logger.level = Logger::Severity::ERROR

      organization = TaskPrompt.ask_for_organization
      recurring_snapshots_backfill_warn_writes_off(organization)

      subscriptions = RecurringAggregationSnapshots::BackfillService.backfillable_subscriptions(organization)
      total = subscriptions.count
      puts "#{total} active subscription(s) with a recurring sum charge and an invoiced period."
      abort "No subscription to backfill." if total.zero?

      TaskPrompt.confirm!("Enqueue a backfill job for each of them? (y/n): ")

      puts "Enqueuing, while #{RecurringAggregationSnapshots::BackfillJob.queue_name} holds less than " \
           "#{RecurringAggregationSnapshots::EnqueueBackfillService::MAX_QUEUE_SIZE} jobs..."
      started_at = Time.current
      enqueued_ids = RecurringAggregationSnapshots::EnqueueBackfillService.call!(organization:).subscription_ids
      not_enqueued_ids = subscriptions.where.not(id: enqueued_ids).pluck(:id)
      puts "Enqueued #{enqueued_ids.size} job(s). Stopping this task leaves them running."

      # Progress comes from Sidekiq alone: the snapshots are read once, at the end. Sidekiq lists a busy
      # worker after a heartbeat of a few seconds, so the loop stops on the second poll with nothing pending.
      enqueued = enqueued_ids.to_set
      idle_polls = 0
      until idle_polls == 2
        Kernel.sleep RECURRING_SNAPSHOTS_BACKFILL_POLL_INTERVAL
        pending = recurring_snapshots_backfill_pending_jobs(enqueued)
        idle_polls = pending.zero? ? idle_polls + 1 : 0
        puts "  #{enqueued.size - pending}/#{enqueued.size} job(s) ran, #{pending} pending"
      end

      backfilled_ids = recurring_snapshots_backfilled_ids(subscriptions, started_at)
      failed_ids = recurring_snapshots_backfill_dead_subscription_ids(started_at) & enqueued_ids
      unwritten_ids = enqueued_ids - backfilled_ids - failed_ids

      puts ""
      puts "Subscriptions backfilled: #{(backfilled_ids - failed_ids).size}/#{total}, failed: #{failed_ids.size}, " \
           "not enqueued: #{not_enqueued_ids.size}, nothing written: #{unwritten_ids.size}"
      recurring_snapshots_backfill_list("Failed, rerun them by listing them in recipes:recurring_aggregation_snapshots:backfill", failed_ids)
      recurring_snapshots_backfill_list("Not enqueued, a job of an earlier run still holds their lock (up to an hour)", not_enqueued_ids)
      recurring_snapshots_backfill_list("Nothing written, no snapshot to store (see Fees::ChargeService)", unwritten_ids)
    end
  end
end

def recurring_snapshots_backfill_warn_writes_off(organization)
  return if organization.feature_flag_enabled?(:recurring_aggregation_snapshots)

  puts "Warning: recurring_aggregation_snapshots is off, so no invoice will write the snapshots of later periods."
end

# The subscriptions a job wrote a marker for since the task started
def recurring_snapshots_backfilled_ids(subscriptions, started_at)
  markers = RecurringAggregationSnapshot
    .where("recurring_aggregation_snapshots.subscription_id = subscriptions.id")
    .where(charge_filter_id: nil)
    .where(watermark: (started_at - RecurringAggregationSnapshot::WATERMARK_LAG).floor(3)..)

  subscriptions.where(markers.arel.exists).pluck(:id)
end

def recurring_snapshots_backfill_list(label, ids)
  return if ids.empty?

  puts "#{label}:"
  puts ids.join(",")
end

# The jobs of this run only: another organization can be backfilled at the same time.
# A job retried by `retry_on` waits in the scheduled set.
def recurring_snapshots_backfill_pending_jobs(subscription_ids)
  entries = Sidekiq::Queue.new(RecurringAggregationSnapshots::BackfillJob.queue_name).to_a +
    Sidekiq::ScheduledSet.new.to_a +
    Sidekiq::Workers.new.map { |_process_id, _thread_id, work| work.job }

  recurring_snapshots_backfill_subscription_ids(entries).count { subscription_ids.include?(it) }
end

def recurring_snapshots_backfill_dead_subscription_ids(started_at)
  recurring_snapshots_backfill_subscription_ids(Sidekiq::DeadSet.new.select { it.at >= started_at }).uniq
end

# Sidekiq stores ActiveJob entries under its wrapper class: `display_class` reads the job's own name,
# and `display_args` the global id of its subscription.
def recurring_snapshots_backfill_subscription_ids(entries)
  entries
    .select { it.display_class == RecurringAggregationSnapshots::BackfillJob.name }
    .filter_map { GlobalID.parse(it.display_args.first)&.model_id }
end

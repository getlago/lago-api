# frozen_string_literal: true

require_relative "../../task_prompt"

namespace :recipes do
  namespace :recurring_aggregation_snapshots do
    desc "Write the snapshots of the latest invoiced period of existing subscriptions"
    task backfill: :environment do
      Rails.logger.level = Logger::Severity::ERROR

      organization = TaskPrompt.ask_for_organization

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
      rescue => e
        failed_subscriptions += 1
        puts "#{label}: not backfilled, #{e.class}: #{e.message}"
      end

      puts ""
      puts "Charges written: #{written}, skipped: #{skipped}, failed: #{failed}, " \
           "subscriptions not backfilled: #{failed_subscriptions}"
    end
  end
end

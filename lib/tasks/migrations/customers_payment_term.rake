# frozen_string_literal: true

# Usage:
#   # Backfill everything:
#   lago exec api bundle exec rails migrations:backfill_customers_payment_term
#
#   # Resume a chain that died, from the last id it reported:
#   lago exec api bundle exec rails migrations:backfill_customers_payment_term START_AFTER=<customer id>

namespace :migrations do
  desc "Enqueue the customers.payment_term backfill on the low_priority queue"
  task backfill_customers_payment_term: :environment do
    Rails.logger.level = Logger::Severity::ERROR

    start_after = ENV["START_AFTER"].presence

    if start_after && !Customer.unscoped.exists?(id: start_after)
      abort "Unknown START_AFTER customer id #{start_after}"
    end

    puts "##################################"
    puts "Customers payment term backfill"
    puts "Starting #{start_after ? "after customer #{start_after}" : "from the beginning"}"
    puts "=" * 50

    DatabaseMigrations::BackfillCustomersPaymentTermJob.perform_later(start_after)

    puts "Enqueued DatabaseMigrations::BackfillCustomersPaymentTermJob"
    puts "- Make sure a Sidekiq worker is draining the low_priority queue"
    puts "- The job logs \"Finished backfilling customers.payment_term\" when the walk is over,"
    puts "  and reports to Sentry if any customer is still missing its term"
  end
end

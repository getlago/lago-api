# frozen_string_literal: true

# Usage:
#   # Backfill everything:
#   lago exec api bundle exec rails migrations:backfill_invoices_search_terms
#
#   # Resume a chain that died, from the last id it reported:
#   lago exec api bundle exec rails migrations:backfill_invoices_search_terms START_AFTER=<invoice id>

namespace :migrations do
  desc "Enqueue the invoices.search_terms backfill on the low_priority queue"
  task backfill_invoices_search_terms: :environment do
    Rails.logger.level = Logger::Severity::ERROR

    start_after = ENV["START_AFTER"].presence

    if start_after && !Invoice.exists?(id: start_after)
      abort "Unknown START_AFTER invoice id #{start_after}"
    end

    puts "##################################"
    puts "Invoices search terms backfill"
    puts "Starting #{start_after ? "after invoice #{start_after}" : "from the beginning"}"
    puts "=" * 50

    DatabaseMigrations::BackfillInvoicesSearchTermsJob.perform_later(start_after)

    puts "Enqueued DatabaseMigrations::BackfillInvoicesSearchTermsJob"
    puts "- Make sure a Sidekiq worker is draining the low_priority queue"
    puts "- The job logs \"Finished backfilling invoices.search_terms\" when the walk is over,"
    puts "  and reports to Sentry if any row is still missing its terms"
  end
end

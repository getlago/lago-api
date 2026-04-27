# frozen_string_literal: true

namespace :migrations do
  desc "Backfill search_text for existing customers"
  task backfill_customer_search_text: :environment do
    DatabaseMigrations::BackfillCustomerSearchTextJob.perform_later
  end
end

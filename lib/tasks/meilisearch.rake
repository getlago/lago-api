# frozen_string_literal: true

namespace :meilisearch do
  desc "Create and configure the Meilisearch invoices index"
  task setup_invoices: :environment do
    MeilisearchClient.setup_invoices_index!
    puts "Meilisearch invoices index configured (#{MeilisearchClient.index_name(MeilisearchClient::INVOICES_INDEX)})"
  end

  desc "Reindex all invoices in Meilisearch"
  task reindex_invoices: :environment do
    count = 0
    Invoice.find_each do |invoice|
      Invoices::SearchIndexJob.perform_later(invoice.id)
      count += 1
    end
    puts "Enqueued reindexing for #{count} invoices"
  end
end

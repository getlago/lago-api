# frozen_string_literal: true

namespace :meilisearch do
  desc "Reindex all invoices in Meilisearch (also applies the index settings)"
  task reindex_invoices: :environment do
    Invoice.reindex!
    puts "Reindexed invoices into #{Invoice.index_uid}"
  end

  desc "Clear the Meilisearch invoices index"
  task clear_invoices: :environment do
    Invoice.clear_index!
    puts "Cleared #{Invoice.index_uid}"
  end
end

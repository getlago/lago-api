# frozen_string_literal: true

module DatabaseMigrations
  class BackfillInvoicesSearchTermsJob < ApplicationJob
    queue_as :low_priority
    unique :until_executed, on_conflict: :log, lock_ttl: 30.minutes

    # ApplicationJob sets retry: 0. The chain is self-terminating, so one failed batch
    # would silently end the whole backfill.
    sidekiq_options retry: 5

    BATCH_SIZE = 5_000
    MAX_PASSES = 2

    def perform(cursor = nil, pass = 1)
      ids = next_ids(cursor)
      return finalize(pass) if ids.empty?

      Invoice.where(id: ids)
        .where("invoices.search_terms IS DISTINCT FROM (#{Invoice::SearchTerms::SQL})")
        .update_all("search_terms = #{Invoice::SearchTerms::SQL}") # rubocop:disable Rails/SkipsModelValidations

      return self.class.perform_later(ids.last, pass) if ids.size == BATCH_SIZE

      finalize(pass)
    end

    def lock_key_arguments
      [arguments]
    end

    private

    def next_ids(cursor)
      scope = Invoice.order(:id).limit(BATCH_SIZE)
      scope = scope.where("invoices.id > ?", cursor) if cursor

      scope.ids
    end

    def finalize(pass)
      unless Invoice.where(search_terms: nil).exists?
        Rails.logger.info("Finished backfilling invoices.search_terms")
        return
      end

      if pass < MAX_PASSES
        self.class.perform_later(nil, pass + 1)
      else
        Rails.logger.error("invoices.search_terms backfill finished with rows still NULL")
        Sentry.capture_message("invoices.search_terms backfill finished with rows still NULL", level: :error)
      end
    end
  end
end

# frozen_string_literal: true

module DatabaseMigrations
  class BackfillCustomersPaymentTermJob < ApplicationJob
    queue_as :low_priority
    unique :until_executed, on_conflict: :log, lock_ttl: 30.minutes

    # ApplicationJob sets retry: 0. The chain is self-terminating, so one failed batch
    # would silently end the whole backfill.
    sidekiq_options retry: 5

    BATCH_SIZE = 5_000

    def perform(cursor = nil)
      ids = next_ids(cursor)
      return finalize if ids.empty?

      pending_customers.where(id: ids)
        .update_all("payment_term = jsonb_build_object('term_type', 'net', 'days', net_payment_term)") # rubocop:disable Rails/SkipsModelValidations

      return self.class.perform_later(ids.last) if ids.size == BATCH_SIZE

      finalize
    end

    def lock_key_arguments
      [arguments]
    end

    private

    def next_ids(cursor)
      scope = Customer.unscoped.order(:id).limit(BATCH_SIZE)
      scope = scope.where("customers.id > ?", cursor) if cursor

      scope.ids
    end

    def pending_customers
      Customer.unscoped.where(payment_term: nil).where.not(net_payment_term: nil)
    end

    def finalize
      unless pending_customers.exists?
        Rails.logger.info("Finished backfilling customers.payment_term")
        return
      end

      Rails.logger.error("customers.payment_term backfill finished with rows still NULL")
      Sentry.capture_message("customers.payment_term backfill finished with rows still NULL", level: :error)
    end
  end
end

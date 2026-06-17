# frozen_string_literal: true

module DatabaseMigrations
  class BackfillWalletTransactionsBillingEntityJob < ApplicationJob
    queue_as :low_priority
    unique :until_executed

    BATCH_SIZE = 1_000

    def perform(batch_number = 1)
      result = ActiveRecord::Base.connection.execute(<<~SQL.squish)
        WITH batch AS (
          SELECT wt.id,
                 COALESCE(i.billing_entity_id, w.billing_entity_id, c.billing_entity_id) AS resolved_billing_entity_id
          FROM wallet_transactions wt
          JOIN wallets w ON w.id = wt.wallet_id
          JOIN customers c ON c.id = w.customer_id
          LEFT JOIN invoices i ON i.id = wt.invoice_id
          WHERE wt.billing_entity_id IS NULL
          LIMIT #{BATCH_SIZE}
        )
        UPDATE wallet_transactions wt
        SET billing_entity_id = batch.resolved_billing_entity_id
        FROM batch
        WHERE wt.id = batch.id
      SQL

      if result.cmd_tuples.positive?
        self.class.perform_later(batch_number + 1)
      else
        Rails.logger.info("Finished backfilling wallet_transactions billing_entity")
      end
    end

    def lock_key_arguments
      [arguments]
    end
  end
end

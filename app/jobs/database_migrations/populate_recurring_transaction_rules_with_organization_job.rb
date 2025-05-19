# frozen_string_literal: true

module DatabaseMigrations
  class PopulateRecurringTransactionRulesWithOrganizationJob < ApplicationJob
    queue_as :low_priority
    unique :until_executed

    BATCH_SIZE = 1000

    def perform(batch_number = 1)
      batch = RecurringTransactionRule.unscoped
        .where(organization_id: nil)
        .limit(BATCH_SIZE)

      if batch.exists?
        # rubocop:disable Rails/SkipsModelValidations
        batch.update_all("organization_id = (SELECT wallets FROM wallets WHERE wallets.id = recurring_transaction_rules.wallet_id)")
        # rubocop:enable Rails/SkipsModelValidations

        # Queue the next batch
        self.class.perform_later(batch_number + 1)
      else
        Rails.logger.info("Finished the execution")
      end
    end

    def lock_key_arguments
      [arguments]
    end
  end
end

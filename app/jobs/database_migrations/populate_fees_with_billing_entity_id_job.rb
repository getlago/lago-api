# frozen_string_literal: true

module DatabaseMigrations
  class PopulateFeesWithBillingEntityIdJob < ApplicationJob
    queue_as :low_priority
    unique :until_executed

    BATCH_SIZE = 1000

    def perform(batch_number = 1)
      batch = Fee.unscoped.where(billing_entity_id: nil).limit(BATCH_SIZE)

      if batch.exists?

        batch.update_all("billing_entity_id = organization_id")

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

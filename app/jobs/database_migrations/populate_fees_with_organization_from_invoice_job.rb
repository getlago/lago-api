# frozen_string_literal: true

module DatabaseMigrations
  class PopulateFeesWithOrganizationFromInvoiceJob < ApplicationJob
    queue_as :low_priority
    unique :until_executed

    BATCH_SIZE = 1000

    def perform(batch_number = 1)
      batch = Fee.unscoped.where(organization_id: nil).where.not(invoice_id: nil)
        .joins(:invoice).limit(BATCH_SIZE)

      if batch.exists?
        # rubocop:disable Rails/SkipsModelValidations
        batch.update_all(
          "organization_id = (SELECT organization_id FROM invoices WHERE invoices.id = fees.invoice_id),
           billing_entity_id = (SELECT organization_id FROM invoices WHERE invoices.id = fees.invoice_id)"
        )
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

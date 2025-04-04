# frozen_string_literal: true

module Migrate
  class PopulateFeesWithOrganizationIdJob < ApplicationJob
    queue_as :low_priority

    class Fee < ApplicationRecord
      belongs_to :invoice, optional: true
    end

    def perform
      batch = Fee.unscoped.where(organization_id: nil).where.not(invoice_id: nil)
                 .joins(:invoice).limit(BATCH_SIZE)

      if batch.exists?
        # rubocop:disable Rails/SkipsModelValidations
        batch.update_all("organization_id = invoices.organization_id, billing_entity_id = invoices.organization_id")

        # Queue the next batch
        self.class.perform_later
      end
    end
  end
end

# frozen_string_literal: true

module Migrate
  class PopulateBatchFeesWithOrganizationIdJob < ApplicationJob
    queue_as :long_running

    class Fee < ApplicationRecord
      belongs_to :invoice, optional: true
      has_one :organization, through: :invoice
    end

    def perform(batch_ids)
      Fee.includes(invoice: :organization).where(id: batch_ids).find_each do |fee|
        fee.update(organization_id: fee.organization.id, billing_entity_id: fee.organization.id, updated_at: fee.updated_at)
      end
    end
  end
end

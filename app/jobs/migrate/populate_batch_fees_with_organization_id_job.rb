# frozen_string_literal: true

module Migrate
  class PopulateBatchFeesWithOrganizationIdJob < ApplicationJob
    queue_as :low_priority

    class Fee < ApplicationRecord
      belongs_to :invoice, optional: true
      has_one :organization, through: :invoice
    end

    # rubocop:disable Rails/SkipsModelValidations
    def perform(batch_ids)
      Fee.includes(:organization).where(id: batch_ids, organization_id: nil).find_each do |fee|
        Fee.no_touching do
          Fee.where(id: fee.id).update_all(
            organization_id: fee.organization.id,
            billing_entity_id: fee.organization.id
          )
        end
      end
    end
    # rubocop:enable Rails/SkipsModelValidations
  end
end

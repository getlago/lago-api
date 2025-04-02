# frozen_string_literal: true

module Migrate
  class PopulateFeesWithOrganizationIdJob < ApplicationJob
    queue_as :low_priority

    def perform
      Fee.where(organization_id: nil).find_in_batches(batch_size: 1000) do |batch|
        PopulateBatchFeesWithOrganizationIdJob.perform_later(batch.pluck(:id))
      end
    end
  end
end

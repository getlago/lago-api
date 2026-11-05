# frozen_string_literal: true

module UsageAttributionValues
  class TrackJob < ApplicationJob
    queue_as :low_priority

    retry_on(*UsageAttributionValuesConsumer::TRANSIENT_ERRORS, wait: :polynomially_longer, attempts: 6)

    def perform(organization_id, entries)
      organization = Organization.find_by(id: organization_id)
      UsageAttributionValues::TrackService.call!(organization:, entries:) if organization
    end
  end
end

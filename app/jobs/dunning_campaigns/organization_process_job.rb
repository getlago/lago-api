# frozen_string_literal: true

module DunningCampaigns
  class OrganizationProcessJob < ApplicationJob
    queue_as :low_priority

    def perform(organization)
      return unless License.premium?

      DunningCampaigns::OrganizationProcessService.call!(organization)
    end
  end
end

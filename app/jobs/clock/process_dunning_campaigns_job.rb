# frozen_string_literal: true

module Clock
  class ProcessDunningCampaignsJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      return unless License.premium?

      Organization.with_auto_dunning_support.find_each do |organization|
        DunningCampaigns::OrganizationProcessJob.perform_later(organization)
      end
    end
  end
end

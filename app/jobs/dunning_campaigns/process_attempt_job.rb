# frozen_string_literal: true

module DunningCampaigns
  class ProcessAttemptJob < ApplicationJob
    queue_as :default

    def perform(customer:, dunning_campaign_threshold:)
      DunningCampaigns::ProcessAttemptService
        .call(customer:, dunning_campaign_threshold:)
        .raise_if_error!
    end
  end
end

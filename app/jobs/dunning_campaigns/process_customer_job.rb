# frozen_string_literal: true

module DunningCampaigns
  class ProcessCustomerJob < ApplicationJob
    queue_as :default

    def perform(customer)
      return unless License.premium?

      result = DunningCampaigns::CheckCustomerService.call!(customer:)

      if result.should_process_customer
        DunningCampaigns::ProcessAttemptJob.perform_later(
          customer: result.customer,
          dunning_campaign_threshold: result.threshold
        )
      end
    end
  end
end
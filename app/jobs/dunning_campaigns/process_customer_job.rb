# frozen_string_literal: true

module DunningCampaigns
  class ProcessCustomerJob < ApplicationJob
    queue_as :low_priority

    unique :until_executed, on_conflict: :log

    def perform(customer)
      DunningCampaigns::ProcessCustomerService.call!(customer:)
    end
  end
end

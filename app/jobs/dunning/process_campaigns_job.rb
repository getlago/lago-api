# frozen_string_literal: true

module Dunning
  class ProcessCampaignsJob < ApplicationJob
    queue_as :default

    def perform
      return unless License.premium?

      DunningCampaigns::BulkProcessService.call.raise_if_error!
    end
  end
end

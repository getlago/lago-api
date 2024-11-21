# frozen_string_literal: true

module Types
  module DunningCampaigns
    class UpdateInput < Types::DunningCampaigns::CreateInput
      graphql_name "UpdateDunningCampaignInput"

      argument :id, ID, required: true
    end
  end
end

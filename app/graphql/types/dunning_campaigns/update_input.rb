# frozen_string_literal: true

module Types
  module DunningCampaigns
    class UpdateInput < Types::BaseInputObject
      graphql_name "UpdateDunningCampaignInput"

      argument :id, ID, required: true

      argument :applied_to_organization, Boolean, required: true
    end
  end
end

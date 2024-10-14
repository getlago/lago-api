# frozen_string_literal: true

module Types
  module DunningCampaigns
    class CreateInput < Types::BaseInputObject
      graphql_name "CreateDunningCampaignInput"

      argument :applied_to_organization, Boolean, required: true
      argument :code, String, required: true
      argument :days_between_attempts, Integer, required: true
      argument :max_attempts, Integer, required: true
      argument :name, String, required: true

      argument :description, String, required: false
    end
  end
end

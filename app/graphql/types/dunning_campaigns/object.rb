# frozen_string_literal: true

module Types
  module DunningCampaigns
    class Object < Types::BaseObject
      graphql_name "DunningCampaign"

      field :id, ID, null: false

      field :applied_to_organization, Boolean, null: false
      field :code, String, null: false
      field :days_between_attempts, Integer, null: false
      field :max_attempts, Integer, null: false
      field :name, String, null: false
      field :thresholds, [Types::DunningCampaignThresholds::Object], null: false

      field :description, String, null: true

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end

# frozen_string_literal: true

module Types
  module DunningCampaignThresholds
    class CreateInput < Types::BaseInputObject
      graphql_name "CreateDunningCampaignThresholdInput"

      argument :amount_cents, GraphQL::Types::BigInt, required: true
      argument :currency, Types::CurrencyEnum, required: true
    end
  end
end

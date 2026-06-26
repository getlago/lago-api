# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module DunningCampaignThresholds
    class Object < Types::BaseObject
      graphql_name "DunningCampaignThreshold"

      field :id, ID, null: false

      field :amount_cents, GraphQL::Types::BigInt, null: false
      field :currency, Types::CurrencyEnum, null: false
    end
  end
end

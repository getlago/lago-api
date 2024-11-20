# frozen_string_literal: true

module Types
  module DunningCampaigns
    class Object < Types::BaseObject
      graphql_name "DunningCampaign"

      field :id, ID, null: false

      field :applied_to_organization, Boolean, null: false
      field :code, String, null: false
      field :customers_count, Integer, null: false
      field :days_between_attempts, Integer, null: false
      field :max_attempts, Integer, null: false
      field :name, String, null: false
      field :thresholds, [Types::DunningCampaignThresholds::Object], null: false

      field :description, String, null: true

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      # rubocop:disable GraphQL/ResolverMethodLength
      def customers_count
        Customer.where(
          <<~SQL.squish,
            exclude_from_dunning_campaign = false
            AND (
              applied_dunning_campaign_id = :campaign_id
              OR (
                applied_dunning_campaign_id IS NULL
                AND organization_id = :organization_id
                AND EXISTS (
                  SELECT 1
                  FROM dunning_campaigns
                  WHERE id = :campaign_id
                  AND applied_to_organization = true
                )
              )
            )
          SQL
          campaign_id: object.id,
          organization_id: object.organization_id
        ).count
      end
      # rubocop:enable GraphQL/ResolverMethodLength
    end
  end
end

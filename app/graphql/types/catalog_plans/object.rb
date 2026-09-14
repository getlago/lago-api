# frozen_string_literal: true

module Types
  module CatalogPlans
    class Object < Types::BaseObject
      graphql_name "CatalogPlan"
      description "A product-catalog plan"

      field :id, ID, null: false
      field :organization, Types::Organizations::OrganizationType

      field :code, String, null: false
      field :description, String, null: true
      field :invoice_display_name, String, null: true
      field :name, String, null: false

      field :currency, Types::CurrencyEnum, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :applied_rate_cards_count, Integer, null: false, description: "Number of rate cards priced on the plan"
      # Any contract attachment freezes the plan's pricing; the UI disables
      # editing and deletion off this flag.
      field :attached_to_contracts, Boolean, null: false
      field :contracts_count, Integer, null: false, description: "Number of contracts on the plan"

      # Batched: a plan list resolves one grouped COUNT per association instead
      # of a query per row. attached_to_contracts shares the contracts count.
      def applied_rate_cards_count
        dataloader.with(Sources::CountByForeignKey, PlanRateCard, :catalog_plan_id).load(object.id)
      end

      def contracts_count
        dataloader.with(Sources::CountByForeignKey, Contract, :catalog_plan_id).load(object.id)
      end

      def attached_to_contracts
        contracts_count.positive?
      end
    end
  end
end

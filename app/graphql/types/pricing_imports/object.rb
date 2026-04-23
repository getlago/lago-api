# frozen_string_literal: true

module Types
  module PricingImports
    class Object < Types::BaseObject
      graphql_name "PricingImport"

      field :id, ID, null: false
      field :state, String, null: false
      field :source_filename, String, null: true

      field :proposed_plan, GraphQL::Types::JSON, null: true
      field :edited_plan, GraphQL::Types::JSON, null: true
      field :execution_report, GraphQL::Types::JSON, null: true

      field :progress_current, Integer, null: false
      field :progress_total, Integer, null: false
      field :error_message, String, null: true

      field :started_at, GraphQL::Types::ISO8601DateTime, null: true
      field :finished_at, GraphQL::Types::ISO8601DateTime, null: true

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end

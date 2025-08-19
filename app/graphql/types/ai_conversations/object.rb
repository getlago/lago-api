# frozen_string_literal: true

module Types
  module AiConversations
    class Object < Types::BaseObject
      graphql_name "AiConversation"

      field :id, ID, null: false
      field :organization, Types::Organizations::OrganizationType, null: false

      field :conversation_id, String, null: false
      field :input_data, String, null: false
      field :status, Types::AiConversations::StatusEnum, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end

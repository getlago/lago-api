# frozen_string_literal: true

module Types
  module AiConversations
    class ToolCall < Types::BaseObject
      graphql_name "AiConversationToolCall"
      description "A write the AI agent asked for, waiting for the member's confirmation"

      field :arguments, GraphQL::Types::JSON, null: false
      field :id, ID, null: false
      field :name, String, null: false
      field :status, Types::AiConversations::ToolCalls::StatusEnum, null: false
    end
  end
end

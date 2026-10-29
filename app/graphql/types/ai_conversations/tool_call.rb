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

      field :batch_answered,
        Boolean,
        null: false,
        description: "Whether every write of this call's batch has an answer, so the agent carries on"

      # Told by the server rather than guessed by the client, as another tab may have answered the others
      def batch_answered
        !object.ai_conversation.tool_calls.unsubmitted.pending.exists?
      end
    end
  end
end

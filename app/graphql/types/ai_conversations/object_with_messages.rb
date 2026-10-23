# frozen_string_literal: true

module Types
  module AiConversations
    class ObjectWithMessages < Types::AiConversations::Object
      graphql_name "AiConversationWithMessages"

      field :messages,
        [Types::AiConversations::Message],
        null: false,
        description: "Messages belonging to this conversation"

      field :pending_tool_calls,
        [Types::AiConversations::ToolCall],
        null: false,
        description: "Writes the AI agent asked for that wait for the member's confirmation"
    end
  end
end

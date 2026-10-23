# frozen_string_literal: true

module Types
  module AiConversations
    class Stream < Types::BaseObject
      graphql_name "AiConversationStream"

      field :chunk, String
      field :done, Boolean, null: false
      field :pending_tool_calls, [Types::AiConversations::ToolCall], null: true
    end
  end
end

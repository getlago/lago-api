# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module AiConversations
    class ObjectWithMessages < Types::AiConversations::Object
      graphql_name "AiConversationWithMessages"

      field :messages,
        [Types::AiConversations::Message],
        null: false,
        description: "Messages belonging to this conversation"
    end
  end
end

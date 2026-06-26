# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module AiConversations
    class Stream < Types::BaseObject
      graphql_name "AiConversationStream"

      field :chunk, String
      field :done, Boolean, null: false
    end
  end
end

# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  class GraphqlSubscriptionType < Types::BaseObject
    field :ai_conversation_streamed, subscription: Types::GraphqlSubscriptions::AiConversation
  end
end

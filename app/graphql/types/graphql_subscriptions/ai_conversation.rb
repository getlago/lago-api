# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module GraphqlSubscriptions
    class AiConversation < Types::BaseSubscription
      argument :id, ID, required: true
      type Types::AiConversations::Stream, null: false

      def subscribe(id:)
        # Return an empty object to keep subscription alive
        {chunk: nil, done: false}
      end

      def update(id:)
        object
      end
    end
  end
end

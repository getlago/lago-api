# frozen_string_literal: true

module Types
  module GraphqlSubscriptions
    class AiConversation < Types::BaseSubscription
      argument :conversation_id, ID, required: true
      type Types::AiConversations::Stream, null: false

      def subscribe(conversation_id:)
        # Return an empty object to keep subscription alive
        { chunk: nil, done: false }
      end

      def update(conversation_id:)
        object
      end
    end
  end
end

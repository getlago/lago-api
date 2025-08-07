# frozen_string_literal: true

module Types
  module GraphqlSubscriptions
    class AiConversation < Types::BaseSubscription
      argument :conversation_id, ID, required: true

      type Types::AiConversations::Object, null: false

      def subscribe(conversation_id:)
        # Optionally return initial value
        conversation_id
      end

      def update(conversation_id:)
        # This method will be triggered with the data you pass in `.trigger`
        # You can just return the object directly
        "foobar"
      end
    end
  end
end

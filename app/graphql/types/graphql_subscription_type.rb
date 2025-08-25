# frozen_string_literal: true

module Types
  class GraphqlSubscriptionType < Types::BaseObject
    field :ai_conversation_streamed, subscription: Types::GraphqlSubscriptions::AiConversation

    def ai_conversation_streamed(conversation_id:)
      # Retour initial pour que la subscription reste ouverte
      AiConversationStream.new(chunk: nil, done: false).tap do
        # Démarre le job après que le client est abonné
        AiConversations::StreamJob.perform_later(conversation_id)
      end
    end
  end
end
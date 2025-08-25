# frozen_string_literal: true

# frozen_string_literal: true

module AiConversations
  class StreamJob < ApplicationJob
    queue_as :default

    def perform(conversation_id)
      ai_conversation = AiConversation.find(conversation_id)

      # Exemple de flux Mistral (ou mock)
      chunks = ["Albert ", "Einstein ", "was ", "a ", "physicist."]

      chunks.each do |chunk|
        stream = AiConversationStream.new(chunk:, done: false)

        LagoApiSchema.subscriptions.trigger(
          :ai_conversation_streamed,
          { conversation_id: ai_conversation.id },
          stream
        )

        sleep 0.5 # simule le streaming temps réel
      end

      # dernier event pour clore le flux
      LagoApiSchema.subscriptions.trigger(
        :ai_conversation_streamed,
        { conversation_id: ai_conversation.id },
        AiConversationStream.new(
          chunk: nil,
          done: true
        )
      )
    end
  end
end
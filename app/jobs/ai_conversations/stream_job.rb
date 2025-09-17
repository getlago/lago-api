# frozen_string_literal: true

module AiConversations
  class StreamJob < ApplicationJob
    queue_as :default

    def perform(ai_conversation, message:)
      AiConversations::StreamService.call!(
        ai_conversation:,
        message:
      )
    end
  end
end

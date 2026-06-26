# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module AiConversations
  class StreamJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_AI_AGENT"])
        :ai_agent
      else
        :default
      end
    end

    unique :until_executed, on_conflict: :log

    def perform(ai_conversation:, message:)
      AiConversations::StreamService.call(ai_conversation:, message:)
    end
  end
end

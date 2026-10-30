# frozen_string_literal: true

module AiConversations
  class ResumeJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_AI_AGENT"])
        :ai_agent
      else
        :default
      end
    end

    unique :until_executed, on_conflict: :log

    # The conversation accepts no new message until its tool results reach the model, so a
    # failure to resume (MCP server or Mistral unavailable) is retried. A retry is safe: writes
    # that already ran are not run again.
    retry_on BaseService::ServiceFailure, wait: :polynomially_longer, attempts: 3

    def perform(ai_conversation)
      AiConversations::ResumeService.call!(ai_conversation:)
    end
  end
end

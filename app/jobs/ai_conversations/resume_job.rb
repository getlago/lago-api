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

    def perform(ai_conversation:)
      AiConversations::ResumeService.call(ai_conversation:)
    end
  end
end

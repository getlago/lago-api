# frozen_string_literal: true

module AiConversations
  # Records the member's answer to a write the agent asked for. Once every write of the
  # batch has an answer, the conversation resumes.
  class DecideToolCallService < BaseService
    Result = BaseResult[:tool_call]

    CANCELLED_RESULT = "The member cancelled this action, so it was not performed. " \
      "Do not try it again unless the member asks for it."

    def initialize(tool_call:, confirmed:)
      @tool_call = tool_call
      @confirmed = confirmed

      super
    end

    def call
      return result.not_found_failure!(resource: "ai_conversation_tool_call") unless tool_call

      decided = false
      ai_conversation.with_lock do
        tool_call.reload

        if tool_call.pending?
          tool_call.update!(
            status: confirmed ? "confirmed" : "cancelled",
            result: confirmed ? nil : CANCELLED_RESULT,
            decided_at: Time.current
          )
          decided = true
        end
      end

      return result.not_allowed_failure!(code: "tool_call_already_decided") unless decided

      AiConversations::ResumeJob.perform_later(ai_conversation:) unless ai_conversation.tool_calls.unsubmitted.pending.exists?

      result.tool_call = tool_call
      result
    end

    private

    attr_reader :tool_call, :confirmed

    def ai_conversation
      tool_call.ai_conversation
    end
  end
end

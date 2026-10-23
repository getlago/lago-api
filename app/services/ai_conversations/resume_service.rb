# frozen_string_literal: true

module AiConversations
  # Carries on a conversation once the member has confirmed or cancelled every write the
  # agent asked for: runs the confirmed ones, then sends all the results of the batch back.
  class ResumeService < StreamService
    def initialize(ai_conversation:)
      super(ai_conversation:, message: nil)
    end

    def call
      return result if tool_calls.empty? || tool_calls.any?(&:pending?)

      super
    end

    private

    def tool_calls
      @tool_calls ||= ai_conversation.tool_calls.unsubmitted.order(:position).to_a
    end

    def stream_response
      tool_results = tool_calls.map { |tool_call| tool_result(tool_call) }

      mistral_agent.submit_tool_results(tool_results, on_submitted: -> { mark_submitted! }) do |chunk|
        stream_chunk(chunk)
      end
    end

    # Only once the model has the results: a failure before that leaves the batch to the next
    # attempt, which does not run the writes again as they are already completed.
    def mark_submitted!
      AiConversationToolCall.where(id: tool_calls.map(&:id))
        .update_all(submitted_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    def tool_result(tool_call)
      tool_call.with_lock { run_confirmed_tool_call(tool_call) if tool_call.confirmed? }

      {tool_call_id: tool_call.tool_call_id, content: tool_call.result}
    end

    def run_confirmed_tool_call(tool_call)
      tool_result = mistral_agent.run_confirmed_tool_call(
        tool_call_id: tool_call.tool_call_id,
        name: tool_call.name,
        arguments: tool_call.arguments
      )

      tool_call.update!(status: "completed", result: tool_result[:content])
    end
  end
end

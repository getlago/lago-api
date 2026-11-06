# frozen_string_literal: true

module AiConversations
  # Carries on a conversation once the member has confirmed or cancelled every write the
  # agent asked for: runs the confirmed ones, then sends all the results of the batch back.
  class ResumeService < StreamService
    INTERRUPTED_RESULT = "This action was started, but the assistant stopped before getting its outcome, " \
      "so it may or may not have been applied. Tell the member to check it before asking for it again."

    def initialize(ai_conversation:)
      super(ai_conversation:, message: nil)
    end

    def call
      return result if tool_calls.any?(&:pending?)

      # Nothing left to send: the results already reached the model in an earlier attempt.
      return finish_resume! if tool_calls.empty?

      super
      finish_resume! if result.success?
      result
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
    # attempt, which never sends a write twice (see #start_execution).
    def mark_submitted!
      AiConversationToolCall.where(id: tool_calls.map(&:id))
        .update_all(submitted_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    def tool_result(tool_call)
      if start_execution(tool_call)
        run_confirmed_tool_call(tool_call)
      elsif tool_call.executing?
        # An earlier attempt stopped after sending the write, so it is never sent twice.
        tool_call.update!(status: "completed", result: INTERRUPTED_RESULT)
      end

      {tool_call_id: tool_call.tool_call_id, content: tool_call.result}
    end

    # Claims a confirmed write before calling the MCP server, so only one attempt ever sends it.
    def start_execution(tool_call)
      tool_call.with_lock do
        next false unless tool_call.confirmed?

        tool_call.update!(status: "executing")
        true
      end
    end

    def run_confirmed_tool_call(tool_call)
      tool_result = mistral_agent.run_confirmed_tool_call(
        tool_call_id: tool_call.tool_call_id,
        name: tool_call.name,
        arguments: tool_call.arguments
      )

      tool_call.update!(status: "completed", result: tool_result[:content])
    end

    def finish_resume!
      ai_conversation.update!(resuming_at: nil)
      result
    end
  end
end

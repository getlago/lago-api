# frozen_string_literal: true

module AiConversations
  # Carries on a conversation once the member has confirmed or cancelled every write the
  # agent asked for. Each round runs the confirmed calls of the batch, sends all its results
  # back, and keeps the tool calls the model makes next before running any of them.
  class ResumeService < StreamService
    INTERRUPTED_RESULT = "This action was started, but the assistant stopped before getting its outcome, " \
      "so it may or may not have been applied. Tell the member to check it before asking for it again."
    STEP_LIMIT_RESULT = "This action was not run: the assistant reached the number of steps it may take " \
      "for one answer. Answer the member with what you have and tell them what is left to do."
    # The batch the member answered, then as many follow-ups as a turn of the agent allows
    MAX_ROUNDS = LagoMcpClient::Mistral::Agent::MAX_ITERATIONS + 1
    # Rounds past MAX_ROUNDS only answer the model's calls with STEP_LIMIT_RESULT
    MAX_EXTRA_ROUNDS = 2

    def initialize(ai_conversation:, final_attempt: true)
      @final_attempt = final_attempt

      super(ai_conversation:, message: nil)
    end

    def call
      tool_calls = unsubmitted_tool_calls

      # Nothing left to send: the results already reached the model in an earlier attempt.
      if tool_calls.empty?
        finish!
        return result
      end

      # An earlier attempt stopped on new writes after keeping them: ask the member about them.
      if tool_calls.any?(&:pending?)
        @pending_tool_calls_saved = tool_calls.select(&:pending?)
        notify_completion
        finish!
        return result
      end

      super
    end

    private

    def unsubmitted_tool_calls
      ai_conversation.tool_calls.unsubmitted.order(:position).to_a
    end

    def stream_response
      (MAX_ROUNDS + MAX_EXTRA_ROUNDS).times do |round|
        tool_calls = unsubmitted_tool_calls
        break if tool_calls.empty?

        if tool_calls.any?(&:pending?)
          @pending_tool_calls_saved = tool_calls.select(&:pending?)
          break
        end

        tool_results = tool_calls.map { |tool_call| tool_result(tool_call) }
        next_tool_calls = mistral_agent.submit_tool_results(tool_results) { |chunk| stream_chunk(chunk) }

        # The model waits for a result of every call, so past the limit they are answered, not dropped.
        save_round!(tool_calls, next_tool_calls, step_limit_reached: round >= MAX_ROUNDS - 1)
      end

      return if @pending_tool_calls_saved.any? || unsubmitted_tool_calls.empty?

      raise "The assistant kept calling tools past its step limit"
    end

    # Only once the model has the results, and together with the calls it makes next: a failure
    # before that sends the batch again, a failure after it runs those calls on the next attempt.
    def save_round!(tool_calls, next_tool_calls, step_limit_reached:)
      ActiveRecord::Base.transaction do
        AiConversationToolCall.where(id: tool_calls.map(&:id))
          .update_all(submitted_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

        next_tool_calls.each.with_index do |tool_call, position|
          save_next_tool_call!(tool_call, position, step_limit_reached:)
        end
      end
    end

    # Reads are kept ready to run, writes wait for the member, refused calls keep their refusal.
    def save_next_tool_call!(tool_call, position, step_limit_reached:)
      decision = tool_guard.decide(tool_call[:name], tool_call[:arguments])
      attributes = if step_limit_reached
        {status: "completed", result: STEP_LIMIT_RESULT}
      elsif decision.refuse?
        {status: "completed", result: decision.message}
      elsif decision.confirm?
        {status: "pending", requires_confirmation: true}
      else
        {status: "confirmed"}
      end

      ai_conversation.tool_calls.create!(
        organization_id: ai_conversation.organization_id,
        membership_id: ai_conversation.membership_id,
        tool_call_id: tool_call[:tool_call_id],
        name: tool_call[:name],
        arguments: tool_call[:arguments],
        position:,
        **attributes
      )
    end

    def tool_result(tool_call)
      if start_execution(tool_call)
        run_confirmed_tool_call(tool_call)
      elsif tool_call.executing? && !tool_call.requires_confirmation?
        # A read that an earlier attempt started is safe to run again.
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

    # An attempt that is retried tells the member nothing, or the error would show as the answer
    # and the retried answer would follow it.
    def handle_error(error)
      return super if @final_attempt

      Rails.logger.error("ResumeService error, retried: #{error.message}")
      result.service_failure!(code: "stream_service_error", message: error.message)
    end

    # The calls the model makes next are saved before they run, so the next message can always
    # start the resume again (see Mutations::AiConversations::Create).
    def release_after_error?
      true
    end
  end
end

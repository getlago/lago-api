# frozen_string_literal: true

module AiConversations
  class StreamService < BaseService
    Result = BaseResult[:ai_conversation]
    CHUNK_DELAY = 0.03

    def initialize(ai_conversation:, message:)
      @ai_conversation = ai_conversation
      @message = message
      @pending_tool_calls_saved = []

      super
    end

    def call
      if mcp_server_url.blank?
        finish!
        return result.forbidden_failure!
      end

      setup_clients!
      stream_response
      save_conversation_id!
      save_pending_tool_calls!
      notify_completion
      finish!
      result.ai_conversation = ai_conversation
      result
    rescue => e
      handle_error(e)
    end

    private

    attr_reader :ai_conversation, :message

    def setup_clients!
      mcp_client.setup!
      mistral_agent.setup!
    end

    def stream_response
      mistral_agent.chat(message) { |chunk| stream_chunk(chunk) }
    end

    def stream_chunk(chunk)
      return if chunk.nil?

      trigger_subscription(chunk:, done: false)
      sleep CHUNK_DELAY
    end

    def save_conversation_id!
      return if mistral_agent.conversation_id.blank?
      return if ai_conversation.mistral_conversation_id == mistral_agent.conversation_id

      ai_conversation.update!(mistral_conversation_id: mistral_agent.conversation_id)
    end

    # The agent stopped on writes that need the member's confirmation. Every call of the
    # batch is kept, with the results of the calls that already ran, until the member decides.
    def save_pending_tool_calls!
      batch = mistral_agent.pending_tool_calls
      return if batch.blank?

      ActiveRecord::Base.transaction do
        batch[:results].each.with_index do |tool_result, position|
          ai_conversation.tool_calls.create!(
            organization_id: ai_conversation.organization_id,
            membership_id: ai_conversation.membership_id,
            tool_call_id: tool_result[:tool_call_id],
            name: tool_result[:name],
            status: "completed",
            result: tool_result[:content],
            position:
          )
        end

        batch[:pending].each.with_index(batch[:results].size) do |tool_call, position|
          @pending_tool_calls_saved << ai_conversation.tool_calls.create!(
            organization_id: ai_conversation.organization_id,
            membership_id: ai_conversation.membership_id,
            tool_call_id: tool_call[:tool_call_id],
            name: tool_call[:name],
            arguments: tool_call[:arguments],
            status: "pending",
            requires_confirmation: true,
            position:
          )
        end
      end
    end

    # The records themselves, so every field of the tool call type resolves, batchAnswered included
    def notify_completion
      trigger_subscription(chunk: nil, done: true, pending_tool_calls: @pending_tool_calls_saved)
    end

    def trigger_subscription(chunk:, done:, pending_tool_calls: [])
      payload = {chunk:, done:}
      payload[:pending_tool_calls] = pending_tool_calls if pending_tool_calls.any?

      LagoApiSchema.subscriptions.trigger(
        :ai_conversation_streamed,
        {id: ai_conversation.id},
        payload
      )
    rescue => e
      Rails.logger.error("Failed to trigger subscription: #{e.message}")
    end

    def handle_error(error)
      Rails.logger.error("StreamService error: #{error.message}")
      Rails.logger.error(error.backtrace.join("\n"))

      trigger_subscription(chunk: "Error: #{error.message}", done: true)
      finish! if release_after_error?
      result.service_failure!(code: "stream_service_error", message: error.message)
    end

    # The model may wait for the results of tool calls that only this attempt knew about. A new
    # message would then reach it out of turn, so the conversation stays closed until BUSY_TIMEOUT.
    def release_after_error?
      !mistral_agent.awaiting_tool_results?
    end

    # Only once the writes the agent stopped on are saved: until then a new message could reach
    # the model while it waits for their results.
    def finish!
      ai_conversation.update!(busy_at: nil)
    end

    def mcp_server_url
      @mcp_server_url ||= ENV["LAGO_MCP_SERVER_URL"]
    end

    def mcp_client
      @mcp_client ||= LagoMcpClient::Client.new(mcp_client_config)
    end

    def mcp_client_config
      @mcp_client_config ||= LagoMcpClient::Config.new(mcp_server_url:, lago_api_key:)
    end

    def mistral_agent
      @mistral_agent ||= LagoMcpClient::Mistral::Agent.new(
        client: mcp_client,
        conversation_id: ai_conversation.mistral_conversation_id,
        tool_guard:
      )
    end

    def tool_guard
      @tool_guard ||= ToolGuard.new(membership: ai_conversation.membership)
    end

    def lago_api_key
      @lago_api_key ||= ai_conversation.organization.api_keys.with_most_permissions.value
    end
  end
end

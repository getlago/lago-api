# frozen_string_literal: true

module LagoMcpClient
  module Mistral
    class Agent
      MAX_ITERATIONS = 2

      # Set when the last turn stopped on tool calls that wait for a confirmation:
      # {results: [...], pending: [...]}. The results of the other calls of the same batch
      # are kept, as the model expects every result of a batch together.
      attr_reader :conversation_id, :pending_tool_calls

      def initialize(client:, conversation_id:, tool_guard: nil)
        @mistral_client = LagoMcpClient::Mistral::Client.new
        @mcp_context = LagoMcpClient::RunContext.new(client:, tool_guard:)
        @conversation_id = conversation_id
        @mutex = Mutex.new
      end

      def setup!
        mcp_context.setup!
        self
      end

      def chat(user_message, max_tool_iterations: MAX_ITERATIONS)
        raise ArgumentError, "Block required for streaming" unless block_given?

        process_conversation(user_message, max_tool_iterations) { |chunk| yield chunk }
      end

      # Sends the results of a batch that waited for a confirmation, then carries on
      # the conversation as #chat does.
      def submit_tool_results(tool_results, max_tool_iterations: MAX_ITERATIONS)
        raise ArgumentError, "Block required for streaming" unless block_given?

        response = send_tool_results(tool_results) { |chunk| yield chunk }
        follow_tool_calls(response, max_tool_iterations) { |chunk| yield chunk }
      end

      def run_confirmed_tool_call(tool_call_id:, name:, arguments:)
        result = mcp_context.process_confirmed_tool_call(tool_call_id:, name:, arguments:)
        format_tool_result(result)
      end

      private

      attr_reader :mistral_client, :mcp_context, :mutex
      attr_writer :conversation_id

      def process_conversation(user_message, max_iterations)
        response = send_message(user_message) { |chunk| yield chunk }
        follow_tool_calls(response, max_iterations) { |chunk| yield chunk }
      end

      def follow_tool_calls(response, max_iterations)
        @pending_tool_calls = nil

        max_iterations.times do |i|
          break unless has_tool_calls?(response)

          outcome = mcp_context.process_tool_calls(response["tool_calls"])
          tool_results = outcome.results.map { |result| format_tool_result(result) }

          if outcome.pending.any?
            @pending_tool_calls = {results: tool_results, pending: outcome.pending}
            return nil
          end

          response = send_tool_results(tool_results) { |chunk| yield chunk }
        end

        extract_final_content(response)
      end

      def send_message(message)
        if conversation_id
          mistral_client.append_to_conversation(
            conversation_id: conversation_id,
            inputs: [{role: "user", content: message}]
          ) { |chunk| yield chunk }
        else
          response = mistral_client.start_conversation(inputs: message) { |chunk| yield chunk }
          self.conversation_id = response["conversation_id"]
          response
        end
      end

      def send_tool_results(tool_results)
        inputs = tool_results.map do |result|
          {
            tool_call_id: result[:tool_call_id],
            result: result[:content],
            type: "function.result",
            object: "entry"
          }
        end

        mistral_client.append_to_conversation(
          conversation_id: conversation_id,
          inputs: inputs
        ) { |chunk| yield chunk }
      end

      def has_tool_calls?(response)
        response["tool_calls"]&.any?
      end

      def format_tool_result(result)
        {
          tool_call_id: result[:tool_call_id] || result["tool_call_id"],
          name: result[:name] || result["name"],
          content: parse_tool_content(result[:content] || result["content"])
        }
      end

      def parse_tool_content(content)
        parsed = JSON.parse(content)
        parsed.dig("content", 0, "text") || content
      rescue JSON::ParserError
        content.to_s
      end

      def extract_final_content(response)
        response.dig("outputs", 0, "content") || ""
      end
    end
  end
end

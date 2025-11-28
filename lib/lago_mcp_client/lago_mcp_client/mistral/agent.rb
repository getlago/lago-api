# frozen_string_literal: true

module LagoMcpClient
  module Mistral
    class Agent
      MAX_ITERATIONS = 2

      def initialize(client:)
        @mistral_client = LagoMcpClient::Mistral::Client.new
        @mcp_context = LagoMcpClient::RunContext.new(client:)
        @conversation_history = []
        @mutex = Mutex.new
      end

      def setup!
        mcp_context.setup!
        self
      end

      def chat(user_message, max_tool_iterations: MAX_ITERATIONS)
        raise ArgumentError, "Block required for streaming" unless block_given?

        add_user_message(user_message)
        process_conversation(max_tool_iterations) { |chunk| yield chunk }
      end

      private

      attr_reader :mistral_client, :mcp_context, :conversation_history, :mutex

      def process_conversation(max_iterations)
        max_iterations.times do |iteration|
          response = stream_assistant_response { |chunk| yield chunk }
          message = extract_message(response)

          return "No response received" unless message
          return handle_final_response(message) unless has_tool_calls?(message)

          handle_tool_calls(message)
        end
      end

      def stream_assistant_response
        mistral_client.chat_completion(
          messages: conversation_history,
          tools: mcp_context.to_model_tools,
          stream: true
        ) { |chunk| yield chunk }
      end

      def has_tool_calls?(message)
        message["tool_calls"]&.any?
      end

      def handle_final_response(message)
        final_content = message["content"] || ""
        add_assistant_message(final_content) unless final_content.strip.empty?
        final_content
      end

      def handle_tool_calls(message)
        add_assistant_message_with_tools(message)
        execute_and_record_tools(message["tool_calls"])
      end

      def add_assistant_message_with_tools(message)
        assistant_msg = {
          role: "assistant",
          content: message["content"] || "",
          tool_calls: message["tool_calls"]
        }
        append_to_history(assistant_msg)
      end

      def execute_and_record_tools(tool_calls)
        tool_results = mcp_context.process_tool_calls(tool_calls)

        tool_results.each do |result|
          tool_message = build_tool_message(result)
          append_to_history(tool_message) if tool_message
        end
      end

      def build_tool_message(result)
        tool_call_id = result[:tool_call_id] || result["tool_call_id"]
        role = result[:role] || result["role"]
        content = result[:content] || result["content"]

        return nil unless tool_call_id && role && content

        {
          role: "tool",
          content: parse_tool_content(content),
          tool_call_id: tool_call_id
        }
      end

      def parse_tool_content(content)
        parsed = JSON.parse(content)
        parsed.dig("content", 0, "text") || content
      rescue JSON::ParserError
        content.to_s
      end

      def add_user_message(content)
        append_to_history({role: "user", content: content})
      end

      def add_assistant_message(content)
        return if content.nil? || content.strip.empty?

        append_to_history({role: "assistant", content: content})
      end

      def append_to_history(message)
        mutex.synchronize { conversation_history << message }
      end

      def extract_text(chunk)
        chunk.dig("choices", 0, "delta", "content").to_s
      rescue
        ""
      end

      def extract_message(response)
        response.dig("choices", 0, "message") if response.is_a?(Hash)
      end
    end
  end
end

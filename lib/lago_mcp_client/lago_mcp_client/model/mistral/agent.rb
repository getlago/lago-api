# frozen_string_literal: true

module LagoMcpClient
  module Model
    module Mistral
      class Agent
        def initialize(client:)
          @mistral_client = Client.new
          @mcp_context = RunContext.new(client:)
          @conversation_history = []
          @mutex = Mutex.new
        end

        def setup!
          @mcp_context.setup!
          self
        end

        def chat(user_message)
          raise "No block given" unless block_given?

          @mutex.synchronize { @conversation_history << { role: "user", content: user_message } }

          assistant_chunk = ""

          begin
            @mcp_context.client.sse_client&.start do |event|
              next unless event.is_a?(Hash) && event[:type] == "message.output.delta"
              chunk = event[:content]
              yield chunk
              assistant_chunk << chunk
            end

            response = @mistral_client.chat_completion(
              messages: @conversation_history,
              tools: @mcp_context.to_model_tools
            )

            message = response.dig("choices", 0, "message")
            if message && message["tool_calls"]
              tool_results = @mcp_context.process_tool_calls(message["tool_calls"])
              tool_results.each do |result|
                yield result["content"]
                @mutex.synchronize { @conversation_history << result }
              end
            end

            unless assistant_chunk.empty?
              @mutex.synchronize { @conversation_history << { role: "assistant", content: assistant_chunk } }
            end
          ensure
            yield nil
          end
        end
      end
    end
  end
end

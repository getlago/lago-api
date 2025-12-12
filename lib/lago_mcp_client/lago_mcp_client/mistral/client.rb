# frozen_string_literal: true

module LagoMcpClient
  module Mistral
    class Client
      MISTRAL_CONVERSATIONS_URL = "https://api.mistral.ai/v1/conversations"

      def start_conversation(inputs:, &block)
        payload = {
          agent_id: ENV["MISTRAL_AGENT_ID"],
          inputs: normalize_inputs(inputs),
          stream: true
        }
        stream_conversation(payload, MISTRAL_CONVERSATIONS_URL, &block)
      end

      def append_to_conversation(conversation_id:, inputs:, &block)
        url = "#{MISTRAL_CONVERSATIONS_URL}/#{conversation_id}"
        payload = {inputs: inputs, stream: true}
        stream_conversation(payload, url, &block)
      end

      private

      def normalize_inputs(inputs)
        if inputs.is_a?(String)
          [{role: "user", content: inputs}]
        else
          inputs
        end
      end

      def stream_conversation(payload, url)
        http_client = LagoHttpClient::Client.new(url, read_timeout: 120)
        headers = {
          "Authorization" => "Bearer #{ENV["MISTRAL_API_KEY"]}",
          "Accept" => "text/event-stream"
        }

        conversation_id = nil
        outputs = []
        tool_calls = []

        http_client.post_with_stream(payload, headers) do |_type, data, _id, _reconnection_time|
          next if data == "[DONE]"

          begin
            parsed_data = JSON.parse(data)
            conversation_id ||= parsed_data["conversation_id"]

            # Handle root-level event types (delta events)
            case parsed_data["type"]
            when "message.output.delta"
              content = parsed_data["content"]
              if content.present?
                yield content if block_given?
              end
            when "conversation.response.done"
              conversation_id ||= parsed_data["conversation_id"]
            when "function.call", "function.call.delta"
              # Handle function calls at root level (delta events accumulate)
              tool_call_id = parsed_data["tool_call_id"]
              existing = tool_calls.find { |tc| tc["id"] == tool_call_id }

              if existing
                # Accumulate arguments for streaming deltas
                existing["function"]["arguments"] = (existing["function"]["arguments"] || "") + (parsed_data["arguments"] || "")
              else
                tool_calls << {
                  "id" => tool_call_id,
                  "type" => "function",
                  "function" => {
                    "name" => parsed_data["name"],
                    "arguments" => parsed_data["arguments"] || ""
                  }
                }
              end
            end

            # Handle outputs array (tool calls, final messages)
            parsed_data["outputs"]&.each do |output|
              case output["type"]
              when "message.output"
                outputs << output
              when "tool.call", "function.call"
                tool_calls << {
                  "id" => output["tool_call_id"] || output["id"],
                  "type" => "function",
                  "function" => {
                    "name" => output["name"] || output.dig("function", "name"),
                    "arguments" => output["arguments"] || output.dig("function", "arguments")
                  }
                }
              end
            end
          rescue JSON::ParserError => e
            Rails.logger.error("Failed to parse SSE data: #{data[0..200]}")
            Rails.logger.error("Parse error: #{e.message}")
          end
        end

        {
          "conversation_id" => conversation_id,
          "outputs" => outputs,
          "tool_calls" => tool_calls.empty? ? nil : tool_calls
        }
      rescue LagoHttpClient::HttpError => e
        raise "Mistral Conversations API Error (#{e.error_code}): #{e.error_body}"
      rescue => e
        raise "Mistral Conversations API streaming error: #{e.message}"
      end
    end
  end
end

# frozen_string_literal: true

module LagoMcpClient
  module Mistral
    class Client
      MISTRAL_CONVERSATIONS_URL = "https://api.mistral.ai/v1/conversations"

      def initialize(api_key: ENV["MISTRAL_API_KEY"], agent_id: ENV["MISTRAL_AGENT_ID"])
        @agent_id = agent_id
        @api_key = api_key
      end

      def start_conversation(inputs:, stream: false, &block)
        payload = {
          agent_id: @agent_id,
          inputs: normalize_inputs(inputs),
          stream: stream
        }

        if stream && block_given?
          stream_conversation(payload, MISTRAL_CONVERSATIONS_URL, &block)
        else
          standard_request(payload, MISTRAL_CONVERSATIONS_URL)
        end
      end

      def append_to_conversation(conversation_id:, inputs:, stream: false, &block)
        url = "#{MISTRAL_CONVERSATIONS_URL}/#{conversation_id}"
        payload = {
          inputs: inputs,
          stream: stream
        }

        if stream && block_given?
          stream_conversation(payload, url, &block)
        else
          standard_request(payload, url)
        end
      end

      private

      def normalize_inputs(inputs)
        if inputs.is_a?(String)
          [{role: "user", content: inputs}]
        else
          inputs
        end
      end

      def stream_conversation(payload, api_url)
        uri = URI(api_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 120

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{@api_key}"
        request["Accept"] = "text/event-stream"
        request.body = JSON.generate(payload)

        conversation_id = nil
        outputs = []
        tool_calls = []
        buffer = ""

        http.request(request) do |response|
          unless response.code == "200"
            error_body = response.body
            raise "Mistral Conversations API Error (#{response.code}): #{error_body}"
          end

          response.read_body do |chunk|
            buffer += chunk

            # SSE events are separated by double newlines
            while buffer.include?("\n\n")
              event_block, buffer = buffer.split("\n\n", 2)
              process_sse_event(event_block) do |data|
                conversation_id ||= data["conversation_id"]

                # Handle root-level event types (delta events)
                case data["type"]
                when "message.output.delta"
                  content = data["content"]
                  if content.present?
                    Rails.logger.debug("Yielding content: #{content}")
                    yield content if block_given?
                  end
                when "conversation.response.done"
                  conversation_id ||= data["conversation_id"]
                  Rails.logger.debug("Conversation done: #{conversation_id}")
                end

                # Handle outputs array (tool calls, final messages)
                data["outputs"]&.each do |output|
                  case output["type"]
                  when "message.output"
                    outputs << output
                  when "tool.call"
                    tool_calls << {
                      "id" => output["tool_call_id"],
                      "type" => "function",
                      "function" => {
                        "name" => output["name"],
                        "arguments" => output["arguments"]
                      }
                    }
                  end
                end
              end
            end
          end
        end

        {
          "conversation_id" => conversation_id,
          "outputs" => outputs,
          "tool_calls" => tool_calls.empty? ? nil : tool_calls
        }
      rescue => e
        Rails.logger.error("Mistral streaming error: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        raise "Mistral Conversations API streaming error: #{e.message}"
      end

      def process_sse_event(event_block)
        data_line = nil

        event_block.split("\n").each do |line|
          line = line.strip
          next if line.empty?

          if line.start_with?("data: ")
            data_line = line.sub(/^data: /, "")
          end
        end

        return unless data_line
        return if data_line == "[DONE]"

        begin
          data = JSON.parse(data_line)
          yield data if block_given?
        rescue JSON::ParserError => e
          Rails.logger.error("Failed to parse SSE data: #{data_line[0..200]}")
          Rails.logger.error("Parse error: #{e.message}")
        end
      end

      def standard_request(payload, api_url)
        uri = URI(api_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 120

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{@api_key}"
        request.body = JSON.generate(payload)

        response = http.request(request)
        response_body = JSON.parse(response.body)

        raise "Mistral Conversations API Error: #{response_body}" unless response.code == "200"

        response_body
      rescue JSON::ParserError => e
        raise "Invalid JSON response from Mistral Conversations API: #{e.message}"
      rescue => e
        raise "Mistral Conversations API connection error: #{e.message}"
      end
    end
  end
end

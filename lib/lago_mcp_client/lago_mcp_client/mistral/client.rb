# frozen_string_literal: true

module LagoMcpClient
  module Mistral
    class Client
      MISTRAL_API_URL = "https://api.mistral.ai/v1/agents/completions"
      MISTRAL_CHAT_API_URL = "https://api.mistral.ai/v1/chat/completions"

      def initialize(api_key: ENV["MISTRAL_API_KEY"], agent_id: ENV["MISTRAL_AGENT_ID"])
        @agent_id = agent_id
        @api_key = api_key
      end

      def chat_completion(messages:, tools: nil, stream: false, use_agent: true, **options, &block)
        base_url = use_agent ? MISTRAL_API_URL : MISTRAL_CHAT_API_URL
        payload = {messages:, **options}

        if use_agent
          payload[:agent_id] = @agent_id
        else
          payload[:model] = options[:model] || "mistral-large-latest"
        end

        payload[:tools] = tools if tools.present?
        payload[:tool_choice] = "auto" if tools.present?
        payload[:stream] = true if stream

        if stream && block_given?
          stream_chat_completion(payload, base_url, &block)
        else
          standard_chat_completion(payload, base_url)
        end
      end

      private

      def stream_chat_completion(payload, api_url)
        uri = URI(api_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 120

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{@api_key}"
        request["Accept"] = "text/event-stream"
        request.body = JSON.generate(payload)

        full_content = ""
        tool_calls = []
        finish_reason = nil
        buffer = ""

        http.request(request) do |response|
          unless response.code == "200"
            error_body = response.body
            raise "Mistral API Error (#{response.code}): #{error_body}"
          end

          response.read_body do |chunk|
            buffer += chunk
            Rails.logger.debug("Received chunk: #{chunk[0..100]}") # Debug

            while buffer.include?("\n")
              line, buffer = buffer.split("\n", 2)
              line = line.strip

              next if line.empty?

              Rails.logger.debug("Processing line: #{line[0..100]}") # Debug

              if line == "data: [DONE]"
                Rails.logger.debug("Received [DONE] signal")
                next
              end

              if line.start_with?("data: ")
                json_str = line.sub(/^data: /, "")

                begin
                  data = JSON.parse(json_str)
                  choice = data.dig("choices", 0)
                  next unless choice

                  delta = choice["delta"]
                  finish_reason = choice["finish_reason"] if choice["finish_reason"]

                  if delta
                    if delta["content"]
                      full_content += delta["content"]
                      Rails.logger.debug("Yielding content: #{delta["content"]}")
                      yield delta["content"] if block_given?
                    end

                    delta["tool_calls"]&.each do |tc|
                      index = tc["index"] || 0

                      tool_calls[index] ||= {
                        "id" => "",
                        "type" => "function",
                        "function" => {"name" => "", "arguments" => ""}
                      }

                      tool_calls[index]["id"] = tc["id"] if tc["id"]
                      tool_calls[index]["type"] = tc["type"] if tc["type"]

                      if tc["function"]
                        if tc["function"]["name"]
                          tool_calls[index]["function"]["name"] += tc["function"]["name"]
                        end

                        if tc["function"]["arguments"]
                          tool_calls[index]["function"]["arguments"] += tc["function"]["arguments"]
                        end
                      end
                    end
                  end
                rescue JSON::ParserError => e
                  Rails.logger.error("Failed to parse SSE line: #{line[0..200]}")
                  Rails.logger.error("Parse error: #{e.message}")
                end
              end
            end
          end
        end

        {
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => full_content.empty? ? nil : full_content,
                "tool_calls" => tool_calls.empty? ? nil : tool_calls.compact
              },
              "finish_reason" => finish_reason
            }
          ]
        }
      rescue => e
        Rails.logger.error("Mistral streaming error: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        raise "Mistral API streaming error: #{e.message}"
      end

      def standard_chat_completion(payload, api_url)
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

        raise "Mistral API Error: #{response_body}" unless response.code == "200"

        response_body
      rescue JSON::ParserError => e
        raise "Invalid JSON response from Mistral API: #{e.message}"
      rescue => e
        raise "Mistral API connection error: #{e.message}"
      end
    end
  end
end

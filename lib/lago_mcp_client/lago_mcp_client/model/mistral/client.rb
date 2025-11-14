# frozen_string_literal

module LagoMcpClient
  module Model
    module Mistral
      class Client
        MISTRAL_API_URL = "https://api.mistral.ai/v1/agents/completions"

        def initialize(api_key: ENV["MISTRAL_API_KEY"], agent_id: ENV["MISTRAL_AGENT_ID"])
          @agent_id = agent_id
          @api_key = api_key
        end

        def chat_completion(messages:, tools: nil, **options)
          payload = { messages:, agent_id: @agent_id, **options }
          payload[:tools] = tools if tools && !tools.empty?
          payload[:tool_choice] = "auto" if tools && !tools.empty?

          uri = URI(MISTRAL_API_URL)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true

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
        rescue StandardError => e
          raise "Mistral API connection error: #{e.message}"
        end
      end
    end
  end
end

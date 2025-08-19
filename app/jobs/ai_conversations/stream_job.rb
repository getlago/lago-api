# frozen_string_literal: true

require "event_stream_parser"

module AiConversations
  class StreamJob < ApplicationJob
    queue_as :default

    def perform(conversation_id)
      ai_conversation = AiConversation.find(conversation_id)

      uri = URI("https://api.mistral.ai/v1/conversations")
      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{ENV.fetch("MISTRAL_API_KEY")}"
      req["Content-Type"] = "application/json"
      req.body = {
        agent_id: "ag:60070909:20250806:lago-billing-assistant:56aead9d",
        inputs: ai_conversation.input_data,
        stream: true,
        store: true
      }.to_json

      parser = EventStreamParser::Parser.new
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(req) do |response|
          response.read_body do |chunk|
            parser.feed(chunk) do |type, data, id, reconnection_time|
              if type == "message.output.delta"
                parsed_data = JSON.parse(data)

                LagoApiSchema.subscriptions.trigger(
                  :ai_conversation_streamed,
                  { conversation_id: ai_conversation.conversation_id },
                  { chunk: parsed_data["content"], done: false }
                )

                sleep 0.1
              end
            end
          end
        end
      end

      LagoApiSchema.subscriptions.trigger(
        :ai_conversation_streamed,
        { conversation_id: ai_conversation.conversation_id },
        { chunk: nil, done: true }
      )
    end
  end
end

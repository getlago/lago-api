# frozen_string_literal: true

module AiConversations
  class StreamService < BaseService
    Result = BaseResult[:ai_conversation]
    MISTRAL_API_URL = "https://api.mistral.ai/v1/conversations"

    def initialize(ai_conversation:, message:)
      @ai_conversation = ai_conversation
      @message = message
      @http = LagoHttpClient::Client.new(MISTRAL_API_URL)
    end

    def call
      @http.post_with_stream(body, headers) do |type, data, _id, _reconnection_time|
        parsed_data = JSON.parse(data)

        if type == "conversation.response.started"
          ai_conversation.update!(mistral_conversation_id: parsed_data["conversation_id"])
        elsif type == "message.output.delta"
          LagoApiSchema.subscriptions.trigger(
            :ai_conversation_streamed,
            { id: ai_conversation.id },
            { chunk: parsed_data["content"], done: false }
          )
        end

        sleep 0.1
      end
      
      
      LagoApiSchema.subscriptions.trigger(
        :ai_conversation_streamed,
        { id: ai_conversation.id },
        { chunk: nil, done: true }
      )
      
      result.success!
    end

    private

    attr_reader :ai_conversation, :message

    def headers
      {
        "Authorization" => "Bearer #{ENV.fetch("MISTRAL_API_KEY")}"
      }
    end

    def body
      {
        agent_id: "ag:60070909:20250806:lago-billing-assistant:56aead9d",
        inputs: message,
        stream: true,
        store: true
      }
    end
  end
end

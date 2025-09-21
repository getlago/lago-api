# frozen_string_literal: true

module AiConversations
  class StreamService < BaseService
    Result = BaseResult[:ai_conversation]

    MISTRAL_CONVERSATIONS_API_URL = "https://api.mistral.ai/v1/conversations"

    def initialize(ai_conversation:, message:)
      @ai_conversation = ai_conversation
      @message = message
      @http = LagoHttpClient::Client.new(api_url)
    end

    def call
      @http.post_with_stream(body, headers) do |type, data, _id, _reconnection_time|
        parsed_data = JSON.parse(data)

        if type == "conversation.response.started" && ai_conversation.mistral_conversation_id.blank?
          ai_conversation.update!(mistral_conversation_id: parsed_data["conversation_id"])
        elsif type == "message.output.delta"
          LagoApiSchema.subscriptions.trigger(
            :ai_conversation_streamed,
            {id: ai_conversation.id},
            {chunk: parsed_data["content"], done: false}
          )
        end

        sleep 0.01
      end

      LagoApiSchema.subscriptions.trigger(
        :ai_conversation_streamed,
        {id: ai_conversation.id},
        {chunk: nil, done: true}
      )
    end

    private

    attr_reader :ai_conversation, :message

    def api_url
      return MISTRAL_CONVERSATIONS_API_URL if ai_conversation.mistral_conversation_id.blank?

      "#{MISTRAL_CONVERSATIONS_API_URL}/#{ai_conversation.mistral_conversation_id}"
    end

    def headers
      {
        "Authorization" => "Bearer #{ENV.fetch("MISTRAL_API_KEY")}"
      }
    end

    def body
      {
        inputs: message,
        stream: true,
        store: true
      }.tap do |body|
        body[:agent_id] = ENV["MISTRAL_AGENT_ID"] if ai_conversation.mistral_conversation_id.blank?
      end
    end
  end
end

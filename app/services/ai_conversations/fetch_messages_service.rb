# frozen_string_literal: true

module AiConversations
  class FetchMessagesService < BaseService
    Result = BaseResult[:ai_conversation]
    MISTRAL_CONVERSATIONS_API_URL = "https://api.mistral.ai/v1/conversations"

    def initialize(ai_conversation:)
      @ai_conversation = ai_conversation
      @http = LagoHttpClient::Client.new(api_url)
    end

    def call
      result = @http.get(headers:)
      result["messages"].map { |h| h.slice("content", "created_at", "type") }
    end

    private

    attr_reader :ai_conversation

    def api_url
      "#{MISTRAL_CONVERSATIONS_API_URL}/#{ai_conversation.mistral_conversation_id}/messages"
    end

    def headers
      {
        "Authorization" => "Bearer #{ENV.fetch("MISTRAL_API_KEY")}"
      }
    end
  end
end

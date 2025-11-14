# frozen_string_literal: true

module AiConversations
  class StreamService < BaseService
    Result = BaseResult[:ai_conversation]

    def initialize(ai_conversation:, message:)
      @ai_conversation = ai_conversation
      @message = message
    end

    def call
      config = LagoMcpClient::Config.new(
        server_url: ENV.fetch("MCP_SERVER_URL", "http://mcp-server:3001/mcp"),
        lago_api_key: ai_conversation.organization.api_keys.first.value
      )
      client = LagoMcpClient::Client.new(config)
      client.setup!

      Rails.logger.info("Creating Mistral agent")
      mistral_agent = LagoMcpClient::Model::Mistral::Agent.new(client:)
      Rails.logger.info("Starting Mistral agent")
      mistral_agent.setup!

      # Stream chat response in real-time
      mistral_agent.chat(message) do |chunk|
        puts "chunk: #{chunk}"
        LagoApiSchema.subscriptions.trigger(
          :ai_conversation_streamed,
          { id: ai_conversation.id },
          { chunk: chunk, done: false }
        )
      end

      # Notify frontend that streaming is done
      LagoApiSchema.subscriptions.trigger(
        :ai_conversation_streamed,
        { id: ai_conversation.id },
        { chunk: nil, done: true }
      )
    end

    private

    attr_reader :ai_conversation, :message
  end
end

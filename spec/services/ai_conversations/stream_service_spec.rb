# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConversations::StreamService do
  subject(:service) { described_class.new(ai_conversation:, message:) }

  let(:ai_conversation) { create(:ai_conversation, mistral_conversation_id: nil) }
  let(:message) { "Hello world" }
  let(:http_client) { instance_double(LagoHttpClient::Client) }

  before do
    allow(LagoHttpClient::Client).to receive(:new).and_return(http_client)
    allow(LagoApiSchema.subscriptions).to receive(:trigger)
  end

  describe "#call" do
    context "when receiving conversation.response.started" do
      let(:conversation_id) { "conv_123" }

      it "updates the ai_conversation with the conversation id" do
        allow(http_client).to receive(:post_with_stream).and_yield(
          "conversation.response.started",
          {conversation_id: conversation_id}.to_json,
          nil,
          nil
        )

        service.call

        expect(ai_conversation.reload.mistral_conversation_id).to eq(conversation_id)
      end
    end

    context "when receiving message.output.delta" do
      let(:chunk) { "partial message" }

      it "triggers a subscription with the chunk" do
        allow(http_client).to receive(:post_with_stream).and_yield(
          "message.output.delta",
          {content: chunk}.to_json,
          nil,
          nil
        )

        service.call

        expect(LagoApiSchema.subscriptions).to have_received(:trigger).with(
          :ai_conversation_streamed,
          {id: ai_conversation.id},
          {chunk:, done: false}
        )
      end
    end

    it "always sends a final done:true event" do
      allow(http_client).to receive(:post_with_stream) # no yield

      service.call

      expect(LagoApiSchema.subscriptions).to have_received(:trigger).with(
        :ai_conversation_streamed,
        {id: ai_conversation.id},
        {chunk: nil, done: true}
      )
    end

    it "sends the agent id if the conversation id is blank" do
      allow(http_client).to receive(:post_with_stream)

      service.call

      expect(http_client).to have_received(:post_with_stream).with(
        {
          inputs: "Hello world",
          stream: true,
          store: true,
          agent_id: ENV["MISTRAL_AGENT_ID"]
        },
        {
          "Authorization" => "Bearer #{ENV["MISTRAL_API_KEY"]}"
        }
      )
    end
  end
end

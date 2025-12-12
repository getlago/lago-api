# frozen_string_literal: true

require "rails_helper"

RSpec.describe LagoMcpClient::Mistral::Client do
  subject(:client) { described_class.new }

  let(:http_client) { instance_double(LagoHttpClient::Client) }
  let(:api_key) { "test_api_key" }
  let(:agent_id) { "test_agent_id" }

  before do
    ENV["MISTRAL_API_KEY"] = api_key
    ENV["MISTRAL_AGENT_ID"] = agent_id
    allow(LagoHttpClient::Client).to receive(:new).and_return(http_client)
  end

  describe "#start_conversation" do
    let(:inputs) { "Hello, how can I help?" }
    let(:conversation_id) { "conv_123" }

    before do
      allow(http_client).to receive(:post_with_stream).and_yield(
        nil,
        {conversation_id:, type: "conversation.response.done"}.to_json,
        nil,
        nil
      )
    end

    it "creates an HTTP client with the conversations URL and timeout" do
      client.start_conversation(inputs:)

      expect(LagoHttpClient::Client).to have_received(:new).with(
        "https://api.mistral.ai/v1/conversations",
        read_timeout: 120
      )
    end

    it "calls post_with_stream with correct payload and headers" do
      client.start_conversation(inputs:)

      expect(http_client).to have_received(:post_with_stream).with(
        {
          agent_id:,
          inputs: [{role: "user", content: inputs}],
          stream: true
        },
        {
          "Authorization" => "Bearer #{api_key}",
          "Accept" => "text/event-stream"
        }
      )
    end

    it "returns the conversation_id" do
      result = client.start_conversation(inputs:)
      expect(result["conversation_id"]).to eq(conversation_id)
    end

    context "when inputs is an array" do
      let(:inputs) { [{role: "user", content: "Hello"}] }

      it "passes inputs as-is without normalizing" do
        client.start_conversation(inputs:)

        expect(http_client).to have_received(:post_with_stream).with(
          hash_including(inputs:),
          anything
        )
      end
    end

    context "when streaming content" do
      let(:chunks) { [] }

      before do
        allow(http_client).to receive(:post_with_stream)
          .and_yield(nil, {type: "message.output.delta", content: "Hello"}.to_json, nil, nil)
          .and_yield(nil, {type: "message.output.delta", content: " world"}.to_json, nil, nil)
          .and_yield(nil, {conversation_id:, type: "conversation.response.done"}.to_json, nil, nil)
      end

      it "yields content chunks" do
        client.start_conversation(inputs:) { |chunk| chunks << chunk }
        expect(chunks).to eq(["Hello", " world"])
      end
    end

    context "when response contains tool calls" do
      let(:tool_call_id) { "call_456" }

      before do
        allow(http_client).to receive(:post_with_stream)
          .and_yield(nil, {
            type: "function.call",
            tool_call_id:,
            name: "get_customer",
            arguments: '{"id": "123"}'
          }.to_json, nil, nil)
          .and_yield(nil, {conversation_id:, type: "conversation.response.done"}.to_json, nil, nil)
      end

      it "returns tool_calls in the response" do
        result = client.start_conversation(inputs:)

        expect(result["tool_calls"]).to eq([
          {
            "id" => tool_call_id,
            "type" => "function",
            "function" => {
              "name" => "get_customer",
              "arguments" => '{"id": "123"}'
            }
          }
        ])
      end
    end

    context "when response contains outputs with messages" do
      before do
        allow(http_client).to receive(:post_with_stream)
          .and_yield(nil, {
            outputs: [{type: "message.output", content: "Final response"}]
          }.to_json, nil, nil)
          .and_yield(nil, {conversation_id:, type: "conversation.response.done"}.to_json, nil, nil)
      end

      it "returns outputs in the response" do
        result = client.start_conversation(inputs:)

        expect(result["outputs"]).to eq([
          {"type" => "message.output", "content" => "Final response"}
        ])
      end
    end

    context "when receiving [DONE] marker" do
      before do
        allow(http_client).to receive(:post_with_stream)
          .and_yield(nil, "[DONE]", nil, nil)
          .and_yield(nil, {conversation_id:, type: "conversation.response.done"}.to_json, nil, nil)
      end

      it "skips the done marker without error" do
        expect { client.start_conversation(inputs:) }.not_to raise_error
      end
    end

    context "when HTTP error occurs" do
      before do
        allow(http_client).to receive(:post_with_stream).and_raise(
          LagoHttpClient::HttpError.new(401, "Unauthorized", URI("https://api.mistral.ai"))
        )
      end

      it "raises a formatted error" do
        expect { client.start_conversation(inputs:) }
          .to raise_error("Mistral Conversations API Error (401): Unauthorized")
      end
    end

    context "when other error occurs" do
      before do
        allow(http_client).to receive(:post_with_stream).and_raise(StandardError.new("Connection failed"))
      end

      it "raises a streaming error" do
        expect { client.start_conversation(inputs:) }
          .to raise_error("Mistral Conversations API streaming error: Connection failed")
      end
    end
  end

  describe "#append_to_conversation" do
    let(:conversation_id) { "conv_existing_789" }
    let(:inputs) { [{role: "user", content: "Follow-up question"}] }

    before do
      allow(http_client).to receive(:post_with_stream).and_yield(
        nil,
        {type: "conversation.response.done"}.to_json,
        nil,
        nil
      )
    end

    it "creates an HTTP client with the conversation-specific URL" do
      client.append_to_conversation(conversation_id:, inputs:)

      expect(LagoHttpClient::Client).to have_received(:new).with(
        "https://api.mistral.ai/v1/conversations/#{conversation_id}",
        read_timeout: 120
      )
    end

    it "calls post_with_stream with correct payload" do
      client.append_to_conversation(conversation_id:, inputs:)

      expect(http_client).to have_received(:post_with_stream).with(
        {inputs:, stream: true},
        {
          "Authorization" => "Bearer #{api_key}",
          "Accept" => "text/event-stream"
        }
      )
    end

    context "when streaming function call deltas" do
      let(:tool_call_id) { "call_delta" }

      before do
        allow(http_client).to receive(:post_with_stream)
          .and_yield(nil, {
            type: "function.call.delta",
            tool_call_id:,
            name: "search",
            arguments: '{"query":'
          }.to_json, nil, nil)
          .and_yield(nil, {
            type: "function.call.delta",
            tool_call_id:,
            arguments: ' "test"}'
          }.to_json, nil, nil)
          .and_yield(nil, {type: "conversation.response.done"}.to_json, nil, nil)
      end

      it "accumulates function call arguments" do
        result = client.append_to_conversation(conversation_id:, inputs:)

        expect(result["tool_calls"]).to eq([
          {
            "id" => tool_call_id,
            "type" => "function",
            "function" => {
              "name" => "search",
              "arguments" => '{"query": "test"}'
            }
          }
        ])
      end
    end

    context "when outputs contain tool.call type" do
      before do
        allow(http_client).to receive(:post_with_stream)
          .and_yield(nil, {
            outputs: [
              {
                type: "tool.call",
                tool_call_id: "tool_123",
                name: "list_customers",
                arguments: "{}"
              }
            ]
          }.to_json, nil, nil)
          .and_yield(nil, {type: "conversation.response.done"}.to_json, nil, nil)
      end

      it "includes tool calls from outputs" do
        result = client.append_to_conversation(conversation_id:, inputs:)

        expect(result["tool_calls"]).to include(
          hash_including(
            "id" => "tool_123",
            "function" => hash_including("name" => "list_customers")
          )
        )
      end
    end
  end
end

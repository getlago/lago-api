# frozen_string_literal: true

require "rails_helper"

RSpec.describe LagoMcpClient::Mistral::Agent do
  subject(:agent) { described_class.new(client: mcp_client, conversation_id:) }

  let(:mcp_client) { instance_double("McpClient") }
  let(:mistral_client) { instance_double(LagoMcpClient::Mistral::Client) }
  let(:mcp_context) { instance_double(LagoMcpClient::RunContext) }
  let(:conversation_id) { nil }

  before do
    allow(LagoMcpClient::Mistral::Client).to receive(:new).and_return(mistral_client)
    allow(LagoMcpClient::RunContext).to receive(:new).with(client: mcp_client, tool_guard: nil).and_return(mcp_context)
  end

  describe "#setup!" do
    before { allow(mcp_context).to receive(:setup!) }

    it "calls setup! on the MCP context" do
      agent.setup!
      expect(mcp_context).to have_received(:setup!)
    end

    it "returns self" do
      expect(agent.setup!).to eq(agent)
    end
  end

  describe "#chat" do
    let(:user_message) { "Hello, assistant!" }
    let(:chunks) { [] }

    context "when no block is given" do
      it "raises an ArgumentError" do
        expect { agent.chat(user_message) }
          .to raise_error(ArgumentError, "Block required for streaming")
      end
    end

    context "when starting a new conversation" do
      let(:conversation_id) { nil }
      let(:new_conversation_id) { "conv_new_456" }
      let(:response) do
        {
          "conversation_id" => new_conversation_id,
          "outputs" => [{"content" => "Hello there!"}]
        }
      end

      before do
        allow(mistral_client).to receive(:start_conversation) do |**_args, &block|
          block&.call("chunk1")
          block&.call("chunk2")
          response
        end
      end

      it "calls start_conversation on mistral client" do
        agent.chat(user_message) { |chunk| chunks << chunk }

        expect(mistral_client).to have_received(:start_conversation).with(
          inputs: user_message
        )
      end

      it "yields streaming chunks" do
        agent.chat(user_message) { |chunk| chunks << chunk }
        expect(chunks).to eq(["chunk1", "chunk2"])
      end

      it "stores the new conversation_id" do
        agent.chat(user_message) { |chunk| chunks << chunk }
        expect(agent.conversation_id).to eq(new_conversation_id)
      end

      it "returns the final content" do
        result = agent.chat(user_message) { |chunk| chunks << chunk }
        expect(result).to eq("Hello there!")
      end
    end

    context "when continuing an existing conversation" do
      let(:conversation_id) { "conv_existing_789" }
      let(:response) do
        {
          "outputs" => [{"content" => "Continued response"}]
        }
      end

      before do
        allow(mistral_client).to receive(:append_to_conversation) do |**_args, &block|
          block&.call("chunk")
          response
        end
      end

      it "calls append_to_conversation on mistral client" do
        agent.chat(user_message) { |chunk| chunks << chunk }

        expect(mistral_client).to have_received(:append_to_conversation).with(
          conversation_id: conversation_id,
          inputs: [{role: "user", content: user_message}]
        )
      end

      it "returns the final content" do
        result = agent.chat(user_message) { |chunk| chunks << chunk }
        expect(result).to eq("Continued response")
      end

      it "keeps the same conversation_id" do
        agent.chat(user_message) { |chunk| chunks << chunk }
        expect(agent.conversation_id).to eq(conversation_id)
      end
    end

    context "when response contains tool calls" do
      let(:conversation_id) { "conv_with_tools" }
      let(:tool_call_id) { "call_123" }
      let(:tool_calls) do
        [
          {
            "id" => tool_call_id,
            "type" => "function",
            "function" => {"name" => "test_tool", "arguments" => "{}"}
          }
        ]
      end
      let(:initial_response) do
        {
          "tool_calls" => tool_calls,
          "outputs" => []
        }
      end
      let(:tool_result) do
        LagoMcpClient::RunContext::ToolCallsOutcome.new(
          results: [
            {
              tool_call_id: tool_call_id,
              name: "test_tool",
              content: '{"content":[{"text":"Tool result text"}]}'
            }
          ],
          pending: []
        )
      end
      let(:final_response) do
        {
          "outputs" => [{"content" => "Task completed successfully"}]
        }
      end

      before do
        call_count = 0
        allow(mistral_client).to receive(:append_to_conversation) do |**_args, &block|
          call_count += 1
          block&.call("chunk#{call_count}")
          (call_count == 1) ? initial_response : final_response
        end

        allow(mcp_context).to receive(:process_tool_calls)
          .with(tool_calls)
          .and_return(tool_result)
      end

      it "processes tool calls via mcp_context" do
        agent.chat(user_message) { |chunk| chunks << chunk }
        expect(mcp_context).to have_received(:process_tool_calls).with(tool_calls)
      end

      it "sends tool results back to the conversation" do
        agent.chat(user_message) { |chunk| chunks << chunk }

        expect(mistral_client).to have_received(:append_to_conversation).with(
          conversation_id: conversation_id,
          inputs: [
            {
              tool_call_id: tool_call_id,
              result: "Tool result text",
              type: "function.result",
              object: "entry"
            }
          ]
        )
      end

      it "makes two API calls (initial + after tool execution)" do
        agent.chat(user_message) { |chunk| chunks << chunk }
        expect(mistral_client).to have_received(:append_to_conversation).twice
      end

      it "returns final assistant response" do
        result = agent.chat(user_message) { |chunk| chunks << chunk }
        expect(result).to eq("Task completed successfully")
      end

      it "yields chunks from both API calls" do
        agent.chat(user_message) { |chunk| chunks << chunk }
        expect(chunks).to eq(["chunk1", "chunk2"])
      end

      it "has no pending tool calls" do
        agent.chat(user_message) { |chunk| chunks << chunk }
        expect(agent.pending_tool_calls).to be_nil
      end

      context "when a tool call waits for a confirmation" do
        let(:tool_result) do
          LagoMcpClient::RunContext::ToolCallsOutcome.new(
            results: [
              {tool_call_id: "call_read", name: "get_coupon", content: '{"content":[{"text":"Coupon"}]}'}
            ],
            pending: [
              {tool_call_id:, name: "create_coupon", arguments: {"code" => "SPRING"}}
            ]
          )
        end

        it "stops before sending any tool result" do
          result = agent.chat(user_message) { |chunk| chunks << chunk }

          expect(result).to be_nil
          expect(mistral_client).to have_received(:append_to_conversation).once
        end

        it "keeps the results of the batch and the pending calls" do
          agent.chat(user_message) { |chunk| chunks << chunk }

          expect(agent.pending_tool_calls).to eq(
            results: [{tool_call_id: "call_read", name: "get_coupon", content: "Coupon"}],
            pending: [{tool_call_id:, name: "create_coupon", arguments: {"code" => "SPRING"}}]
          )
        end
      end
    end
  end

  describe "#submit_tool_results" do
    let(:conversation_id) { "conv_resumed" }
    let(:tool_results) { [{tool_call_id: "call_123", content: "Coupon created"}] }

    before do
      allow(mistral_client).to receive(:append_to_conversation) do |**_args, &block|
        block&.call("Done")
        {"outputs" => [{"content" => "The coupon was created"}]}
      end
    end

    it "sends the results and returns the final content" do
      chunks = []
      result = agent.submit_tool_results(tool_results) { |chunk| chunks << chunk }

      expect(result).to eq("The coupon was created")
      expect(chunks).to eq(["Done"])
      expect(mistral_client).to have_received(:append_to_conversation).with(
        conversation_id:,
        inputs: [{tool_call_id: "call_123", result: "Coupon created", type: "function.result", object: "entry"}]
      )
    end

    it "calls on_submitted once the model has the results" do
      calls = []
      allow(mistral_client).to receive(:append_to_conversation) do |**_args, &block|
        calls << :append
        {"outputs" => [{"content" => "The coupon was created"}]}
      end

      agent.submit_tool_results(tool_results, on_submitted: -> { calls << :submitted }) { |_chunk| }

      expect(calls).to eq(%i[append submitted])
    end

    context "when the model does not accept the results" do
      before do
        allow(mistral_client).to receive(:append_to_conversation).and_raise(LagoMcpClient::Mistral::ApiError.new(503, "unavailable"))
      end

      it "does not call on_submitted" do
        submitted = false

        expect { agent.submit_tool_results(tool_results, on_submitted: -> { submitted = true }) { |_chunk| } }
          .to raise_error(LagoMcpClient::Mistral::ApiError)
        expect(submitted).to be(false)
      end
    end

    it "requires a block" do
      expect { agent.submit_tool_results(tool_results) }.to raise_error(ArgumentError)
    end
  end

  describe "#run_confirmed_tool_call" do
    before do
      allow(mcp_context).to receive(:process_confirmed_tool_call)
        .with(tool_call_id: "call_123", name: "create_coupon", arguments: {"code" => "SPRING"})
        .and_return({tool_call_id: "call_123", name: "create_coupon", content: '{"content":[{"text":"Created"}]}'})
    end

    it "runs the call through the MCP context and formats the result" do
      result = agent.run_confirmed_tool_call(tool_call_id: "call_123", name: "create_coupon", arguments: {"code" => "SPRING"})

      expect(result).to eq(tool_call_id: "call_123", name: "create_coupon", content: "Created")
    end
  end
end

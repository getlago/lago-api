# frozen_string_literal: true

require "rails_helper"

RSpec.describe LagoMcpClient::Mistral::Agent do
  let(:mcp_client) { instance_double("McpClient") }
  let(:mistral_client) { instance_double(LagoMcpClient::Mistral::Client) }
  let(:run_context) { instance_double(LagoMcpClient::RunContext) }
  let(:agent) { described_class.new(client: mcp_client) }

  before do
    allow(LagoMcpClient::Mistral::Client).to receive(:new).and_return(mistral_client)
    allow(LagoMcpClient::RunContext).to receive(:new).with(client: mcp_client).and_return(run_context)
  end

  describe "#setup!" do
    before { allow(run_context).to receive(:setup!) }

    it "calls setup! on the MCP context" do
      agent.setup!
      expect(run_context).to have_received(:setup!)
    end

    it "returns self" do
      expect(agent.setup!).to eq(agent)
    end
  end

  describe "#chat" do
    let(:user_message) { "Hello, assistant!" }
    let(:model_tools) { [{"type" => "function", "function" => {"name" => "test_tool"}}] }
    let(:chunks) { [] }

    before do
      allow(run_context).to receive(:to_model_tools).and_return(model_tools)
    end

    context "when no block is given" do
      it "raises an ArgumentError" do
        expect { agent.chat(user_message) }
          .to raise_error(ArgumentError, "Block required for streaming")
      end
    end

    context "when streaming without tool calls" do
      let(:chunk1) { {"choices" => [{"delta" => {"content" => "Hello"}}]} }
      let(:chunk2) { {"choices" => [{"delta" => {"content" => " there"}}]} }
      let(:response) { {"choices" => [{"message" => {"content" => "Hello there"}}]} }

      before do
        allow(mistral_client).to receive(:chat_completion) do |**args, &block|
          block&.call(chunk1)
          block&.call(chunk2)
          response
        end
      end

      it "appends user message to history" do
        agent.chat(user_message) { |chunk| chunks << chunk }
        history = agent.instance_variable_get(:@conversation_history)
        expect(history.first).to eq({role: "user", content: user_message})
      end

      it "yields streaming chunks" do
        agent.chat(user_message) { |chunk| chunks << chunk }
        expect(chunks).to include(chunk1, chunk2)
      end

      it "appends assistant message to history" do
        agent.chat(user_message) { |chunk| chunks << chunk }
        history = agent.instance_variable_get(:@conversation_history)
        expect(history.last).to eq({role: "assistant", content: "Hello there"})
      end

      it "returns the final content" do
        result = agent.chat(user_message) { |chunk| chunks << chunk }
        expect(result).to eq("Hello there")
      end
    end

    context "when streaming with tool calls" do
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
      let(:first_response) do
        {
          "choices" => [
            {
              "message" => {
                "content" => "",
                "tool_calls" => tool_calls
              }
            }
          ]
        }
      end
      let(:tool_results) do
        [
          {
            "role" => "tool",
            "content" => "{\"content\":[{\"text\":\"Tool result\"}]}",
            "tool_call_id" => tool_call_id
          }
        ]
      end
      let(:final_response) do
        {
          "choices" => [
            {
              "message" => {
                "content" => "Task completed successfully"
              }
            }
          ]
        }
      end

      before do
        allow(mistral_client).to receive(:chat_completion)
          .and_return(first_response, final_response)
        allow(run_context).to receive(:process_tool_calls)
          .with(tool_calls)
          .and_return(tool_results)
      end

      it "processes tool calls" do
        agent.chat(user_message) { |chunk| chunks << chunk }
        expect(run_context).to have_received(:process_tool_calls).with(tool_calls)
      end

      it "appends assistant message with tool_calls to history" do
        agent.chat(user_message) { |chunk| chunks << chunk }
        history = agent.instance_variable_get(:@conversation_history)

        assistant_msg = history.find { |msg| msg[:role] == "assistant" && msg[:tool_calls] }
        expect(assistant_msg).to include(role: "assistant", content: "", tool_calls:)
      end

      it "appends tool results to history" do
        agent.chat(user_message) { |chunk| chunks << chunk }
        history = agent.instance_variable_get(:@conversation_history)

        tool_msg = history.find { |msg| msg[:role] == "tool" }
        expect(tool_msg).to include(role: "tool", content: "Tool result", tool_call_id:)
      end

      it "returns final assistant response" do
        result = agent.chat(user_message) { |chunk| chunks << chunk }
        expect(result).to eq("Task completed successfully")
      end

      it "makes two API calls (initial + after tool execution)" do
        agent.chat(user_message) { |chunk| chunks << chunk }
        expect(mistral_client).to have_received(:chat_completion).twice
      end
    end

    context "when response is nil or invalid" do
      before do
        allow(mistral_client).to receive(:chat_completion).and_return(nil)
      end

      it "returns 'No response received'" do
        result = agent.chat(user_message) { |chunk| chunks << chunk }
        expect(result).to eq("No response received")
      end
    end
  end
end

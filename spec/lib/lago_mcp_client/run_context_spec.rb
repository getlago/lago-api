# frozen_string_literal: true

require "rails_helper"

RSpec.describe LagoMcpClient::RunContext do
  subject(:run_context) { described_class.new(client:) }

  let(:client) { instance_double("LagoMcpClient::Client") }
  let(:tool_sum) { instance_double("LagoMcpClient::Tool", name: "sum", description: "Adds numbers", input_schema: {"a" => "int", "b" => "int"}) }
  let(:tool_echo) { instance_double("LagoMcpClient::Tool", name: "echo", description: "Echoes text", input_schema: {"msg" => "string"}) }

  describe "#setup!" do
    it "loads tools from the client and returns self" do
      allow(client).to receive(:list_tools).and_return([tool_sum, tool_echo])

      result = run_context.setup!

      expect(result).to eq(run_context)
      expect(run_context.to_model_tools.map { |t| t[:function][:name] }).to contain_exactly("sum", "echo")
    end
  end

  describe "#to_model_tools" do
    before do
      allow(client).to receive(:list_tools).and_return([tool_sum])
      run_context.setup!
    end

    it "returns formatted model tool definitions" do
      expect(run_context.to_model_tools).to eq([
        {
          type: "function",
          function: {
            name: "sum",
            description: "Adds numbers",
            parameters: {"a" => "int", "b" => "int"}
          }
        }
      ])
    end
  end

  describe "#process_tool_calls" do
    before do
      allow(client).to receive(:list_tools).and_return([tool_sum])
      run_context.setup!
      allow(client).to receive(:call_tool).with("sum", {"a" => 1, "b" => 2}).and_return({"result" => 3})
    end

    let(:tool_call) do
      {
        "id" => "123",
        "function" => {
          "name" => "sum",
          "arguments" => '{"a":1,"b":2}'
        }
      }
    end

    it "executes a valid tool call and returns JSON-formatted results" do
      result = run_context.process_tool_calls([tool_call])

      expect(result.results).to eq([
        {
          tool_call_id: "123",
          name: "sum",
          role: "tool",
          content: JSON.generate({"result" => 3})
        }
      ])
      expect(result.pending).to be_empty
    end

    it "raises an error if the tool does not exist" do
      fake_call = {
        "id" => "456",
        "function" => {"name" => "missing", "arguments" => "{}"}
      }

      expect { run_context.process_tool_calls([fake_call]) }.to raise_error("Tool 'missing' not found")
    end
  end

  context "with a tool guard" do
    subject(:run_context) { described_class.new(client:, tool_guard:) }

    let(:tool_guard) { instance_double("ToolGuard") }
    let(:tool_create) { instance_double("LagoMcpClient::Tool", name: "create", description: "Creates", input_schema: {}) }

    let(:tool_calls) do
      [
        {"id" => "1", "function" => {"name" => "sum", "arguments" => '{"a":1,"b":2}'}},
        {"id" => "2", "function" => {"name" => "echo", "arguments" => '{"msg":"hi"}'}},
        {"id" => "3", "function" => {"name" => "create", "arguments" => '{"code":"X"}'}}
      ]
    end

    before do
      allow(client).to receive(:list_tools).and_return([tool_sum, tool_echo, tool_create])
      allow(tool_guard).to receive(:exposed?) { |name| name != "echo" }
      allow(tool_guard).to receive(:decide).with("sum", {"a" => 1, "b" => 2}).and_return(LagoMcpClient::ToolDecision.run)
      allow(tool_guard).to receive(:decide).with("echo", {"msg" => "hi"}).and_return(LagoMcpClient::ToolDecision.refuse("Not allowed"))
      allow(tool_guard).to receive(:decide).with("create", {"code" => "X"}).and_return(LagoMcpClient::ToolDecision.confirm)
      allow(client).to receive(:call_tool).with("sum", {"a" => 1, "b" => 2}).and_return({"result" => 3})
      allow(client).to receive(:call_tool).with("create", {"code" => "X"}).and_return({"created" => true})

      run_context.setup!
    end

    it "only exposes the tools the guard allows" do
      expect(run_context.to_model_tools.map { |t| t[:function][:name] }).to contain_exactly("sum", "create")
    end

    it "runs allowed calls, refuses denied ones and holds the ones to confirm" do
      outcome = run_context.process_tool_calls(tool_calls)

      expect(outcome.results).to eq([
        {tool_call_id: "1", name: "sum", role: "tool", content: JSON.generate({"result" => 3})},
        {
          tool_call_id: "2",
          name: "echo",
          role: "tool",
          content: JSON.generate({"content" => [{"type" => "text", "text" => "Not allowed"}], "isError" => true})
        }
      ])
      expect(outcome.pending).to eq([{tool_call_id: "3", name: "create", arguments: {"code" => "X"}}])
      expect(client).not_to have_received(:call_tool).with("echo", anything)
      expect(client).not_to have_received(:call_tool).with("create", anything)
    end

    describe "#process_confirmed_tool_call" do
      it "runs the confirmed call" do
        result = run_context.process_confirmed_tool_call(tool_call_id: "3", name: "create", arguments: {"code" => "X"})

        expect(result).to eq(tool_call_id: "3", name: "create", role: "tool", content: JSON.generate({"created" => true}))
      end

      it "refuses the call when the guard now refuses it" do
        allow(tool_guard).to receive(:decide).with("create", {"code" => "X"}).and_return(LagoMcpClient::ToolDecision.refuse("Lost permission"))

        result = run_context.process_confirmed_tool_call(tool_call_id: "3", name: "create", arguments: {"code" => "X"})

        expect(JSON.parse(result[:content])).to eq("content" => [{"type" => "text", "text" => "Lost permission"}], "isError" => true)
        expect(client).not_to have_received(:call_tool).with("create", anything)
      end
    end
  end
end

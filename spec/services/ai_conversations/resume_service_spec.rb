# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConversations::ResumeService do
  subject(:service) { described_class.new(ai_conversation:) }

  let(:organization) { create(:organization) }
  let(:permissions) { %w[ai_conversations:create ai_conversations:view coupons:view coupons:create] }
  let(:role) { create(:role, organization:, permissions:) }
  let(:membership) { create(:membership, organization:, role:) }
  let(:ai_conversation) { create(:ai_conversation, organization:, membership:) }

  let(:mcp_client) { instance_double(LagoMcpClient::Client, setup!: nil, list_tools: tools) }
  let(:tools) { [LagoMcpClient::Tool.new(name: "create_coupon", description: "Creates a coupon", input_schema: {})] }
  let(:mistral_client) { instance_double(LagoMcpClient::Mistral::Client) }

  let!(:read_call) do
    create(:ai_conversation_tool_call, ai_conversation:, name: "get_coupon", status: "completed", result: "No coupon", requires_confirmation: false, position: 0)
  end
  let!(:write_call) do
    create(:ai_conversation_tool_call, ai_conversation:, name: "create_coupon", arguments: {"coupon" => {"code" => "SPRING"}}, status: write_status, position: 1)
  end
  let(:write_status) { "confirmed" }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("LAGO_MCP_SERVER_URL").and_return("http://localhost:3001")
    allow(LagoMcpClient::Client).to receive(:new).and_return(mcp_client)
    allow(LagoMcpClient::Mistral::Client).to receive(:new).and_return(mistral_client)
    allow(mcp_client).to receive(:call_tool).and_return({"content" => [{"type" => "text", "text" => "Coupon SPRING created"}]})
    allow(mistral_client).to receive(:append_to_conversation) do |**_args, &block|
      block&.call("Done")
      {"outputs" => [{"content" => "Done"}]}
    end
    allow(LagoApiSchema.subscriptions).to receive(:trigger)
    stub_const("AiConversations::StreamService::CHUNK_DELAY", 0)
  end

  it "runs the confirmed write and sends every result of the batch" do
    freeze_time do
      expect(service.call).to be_success

      expect(mcp_client).to have_received(:call_tool).with("create_coupon", {"coupon" => {"code" => "SPRING"}})
      expect(write_call.reload).to have_attributes(status: "completed", result: "Coupon SPRING created", submitted_at: Time.current)
      expect(read_call.reload.submitted_at).to eq(Time.current)
      expect(mistral_client).to have_received(:append_to_conversation).with(
        conversation_id: ai_conversation.mistral_conversation_id,
        inputs: [
          {tool_call_id: read_call.tool_call_id, result: "No coupon", type: "function.result", object: "entry"},
          {tool_call_id: write_call.tool_call_id, result: "Coupon SPRING created", type: "function.result", object: "entry"}
        ]
      )
      expect(LagoApiSchema.subscriptions).to have_received(:trigger).with(:ai_conversation_streamed, {id: ai_conversation.id}, {chunk: "Done", done: false})
      expect(LagoApiSchema.subscriptions).to have_received(:trigger).with(:ai_conversation_streamed, {id: ai_conversation.id}, {chunk: nil, done: true})
    end
  end

  context "when Mistral does not accept the results" do
    before do
      allow(mistral_client).to receive(:append_to_conversation).and_raise(LagoMcpClient::Mistral::ApiError.new(503, "unavailable"))
    end

    it "keeps the batch for the next attempt without running the write again" do
      expect(service.call).to be_failure
      expect(write_call.reload).to have_attributes(status: "completed", submitted_at: nil)
      expect(read_call.reload.submitted_at).to be_nil

      described_class.new(ai_conversation:).call

      expect(mcp_client).to have_received(:call_tool).once
    end
  end

  context "when the member lost the permission after confirming" do
    let(:permissions) { %w[ai_conversations:create ai_conversations:view coupons:view] }

    it "does not create the coupon" do
      service.call

      expect(mcp_client).not_to have_received(:call_tool)
      expect(write_call.reload.status).to eq("completed")
      expect(write_call.result).to include("coupons:create")
    end
  end

  context "when the member cancelled the write" do
    let(:write_status) { "cancelled" }

    before { write_call.update!(result: AiConversations::DecideToolCallService::CANCELLED_RESULT) }

    it "sends the cancellation without running the write" do
      service.call

      expect(mcp_client).not_to have_received(:call_tool)
      expect(mistral_client).to have_received(:append_to_conversation).with(
        conversation_id: ai_conversation.mistral_conversation_id,
        inputs: include(
          {tool_call_id: write_call.tool_call_id, result: AiConversations::DecideToolCallService::CANCELLED_RESULT, type: "function.result", object: "entry"}
        )
      )
    end
  end

  context "when a write of the batch still waits for the member" do
    let(:write_status) { "pending" }

    it "does nothing" do
      expect(service.call).to be_success
      expect(LagoMcpClient::Client).not_to have_received(:new)
      expect(mistral_client).not_to have_received(:append_to_conversation)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConversations::ResumeService do
  subject(:service) { described_class.new(ai_conversation:) }

  let(:organization) { create(:organization) }
  let(:permissions) { %w[ai_conversations:create ai_conversations:view coupons:view coupons:create] }
  let(:role) { create(:role, organization:, permissions:) }
  let(:membership) { create(:membership, organization:, role:) }
  let(:ai_conversation) { create(:ai_conversation, organization:, membership:, resuming_at: 1.minute.ago) }

  let(:mcp_client) { instance_double(LagoMcpClient::Client, setup!: nil, list_tools: tools) }
  let(:tools) do
    [
      LagoMcpClient::Tool.new(name: "create_coupon", description: "Creates a coupon", input_schema: {}),
      LagoMcpClient::Tool.new(name: "get_coupon", description: "Gets a coupon", input_schema: {})
    ]
  end
  let(:mistral_client) { instance_double(LagoMcpClient::Mistral::Client) }

  let!(:read_call) do
    create(:ai_conversation_tool_call, ai_conversation:, name: "get_coupon", status: "completed", result: "No coupon", requires_confirmation: false, position: 0)
  end
  let!(:write_call) do
    create(:ai_conversation_tool_call, ai_conversation:, name: "create_coupon", arguments: {"coupon" => {"code" => "SPRING"}}, status: write_status, position: 1)
  end
  let(:write_status) { "confirmed" }
  let(:nonce) { "fedcba9876543210fedcba9876543210" }

  def wrapped(text)
    "#{LagoMcpClient::Mistral::Agent::UNTRUSTED_DATA_NOTICE}\n<untrusted_data_#{nonce}>\n#{text}\n</untrusted_data_#{nonce}>"
  end

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
    allow(SecureRandom).to receive(:hex).and_call_original
    allow(SecureRandom).to receive(:hex).with(16).and_return(nonce)
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
          {tool_call_id: read_call.tool_call_id, result: wrapped("No coupon"), type: "function.result", object: "entry"},
          {tool_call_id: write_call.tool_call_id, result: wrapped("Coupon SPRING created"), type: "function.result", object: "entry"}
        ]
      )
      expect(LagoApiSchema.subscriptions).to have_received(:trigger).with(:ai_conversation_streamed, {id: ai_conversation.id}, {chunk: "Done", done: false})
      expect(LagoApiSchema.subscriptions).to have_received(:trigger).with(:ai_conversation_streamed, {id: ai_conversation.id}, {chunk: nil, done: true})
      expect(ai_conversation.reload.resuming_at).to be_nil
    end
  end

  context "when an earlier attempt stopped after sending the write" do
    let(:write_status) { "executing" }

    it "does not send the write again and tells the model its outcome is unknown" do
      service.call

      expect(mcp_client).not_to have_received(:call_tool)
      expect(write_call.reload).to have_attributes(status: "completed", result: described_class::INTERRUPTED_RESULT)
      expect(mistral_client).to have_received(:append_to_conversation).with(
        conversation_id: ai_conversation.mistral_conversation_id,
        inputs: include(
          {tool_call_id: write_call.tool_call_id, result: wrapped(described_class::INTERRUPTED_RESULT), type: "function.result", object: "entry"}
        )
      )
    end
  end

  context "when the attempt stops while the write is in flight" do
    before { allow(mcp_client).to receive(:call_tool).and_raise(Net::ReadTimeout) }

    it "never sends the write twice" do
      expect(service.call).to be_failure
      expect(write_call.reload.status).to eq("executing")

      described_class.new(ai_conversation:).call

      expect(mcp_client).to have_received(:call_tool).once
      expect(write_call.reload).to have_attributes(status: "completed", result: described_class::INTERRUPTED_RESULT)
    end
  end

  context "when Mistral does not accept the results" do
    before do
      allow(mistral_client).to receive(:append_to_conversation).and_raise(LagoMcpClient::Mistral::ApiError.new(503, "unavailable"))
    end

    it "tells the member about the failure on the last attempt" do
      service.call

      expect(LagoApiSchema.subscriptions).to have_received(:trigger)
        .with(:ai_conversation_streamed, {id: ai_conversation.id}, {chunk: start_with("Error:"), done: true})
    end

    context "when the attempt will be retried" do
      subject(:service) { described_class.new(ai_conversation:, final_attempt: false) }

      it "fails without telling the member" do
        expect(service.call).to be_failure
        expect(LagoApiSchema.subscriptions).not_to have_received(:trigger)
      end
    end

    it "keeps the batch for the next attempt without running the write again" do
      expect(service.call).to be_failure
      expect(write_call.reload).to have_attributes(status: "completed", submitted_at: nil)
      expect(read_call.reload.submitted_at).to be_nil

      described_class.new(ai_conversation:).call

      expect(mcp_client).to have_received(:call_tool).once
      expect(ai_conversation.reload.resuming_at).to be_present
    end
  end

  context "when the results already reached the model in an earlier attempt" do
    before { AiConversationToolCall.update_all(status: "completed", submitted_at: Time.current) } # rubocop:disable Rails/SkipsModelValidations

    it "only ends the resume" do
      expect(service.call).to be_success
      expect(mistral_client).not_to have_received(:append_to_conversation)
      expect(ai_conversation.reload.resuming_at).to be_nil
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
          {tool_call_id: write_call.tool_call_id, result: wrapped(AiConversations::DecideToolCallService::CANCELLED_RESULT), type: "function.result", object: "entry"}
        )
      )
    end
  end

  context "when the model answers the results with more tool calls" do
    let(:next_tool_calls) { [{"id" => "call_next", "function" => {"name" => next_tool, "arguments" => '{"code":"SPRING"}'}}] }
    let(:next_tool) { "get_coupon" }

    before do
      responses = [{"tool_calls" => next_tool_calls}, {"outputs" => [{"content" => "Done"}]}]
      allow(mistral_client).to receive(:append_to_conversation) do |**_args, &block|
        block&.call("Done")
        responses.shift
      end
      allow(mcp_client).to receive(:call_tool).with("get_coupon", {"code" => "SPRING"})
        .and_return({"content" => [{"type" => "text", "text" => "Coupon SPRING"}]})
    end

    it "keeps the read, runs it and sends its result" do
      expect(service.call).to be_success

      next_call = ai_conversation.tool_calls.find_by!(tool_call_id: "call_next")
      expect(next_call).to have_attributes(status: "completed", result: "Coupon SPRING", requires_confirmation: false, submitted_at: be_present)
      expect(mistral_client).to have_received(:append_to_conversation).with(
        conversation_id: ai_conversation.mistral_conversation_id,
        inputs: [{tool_call_id: "call_next", result: wrapped("Coupon SPRING"), type: "function.result", object: "entry"}]
      )
      expect(ai_conversation.reload.resuming_at).to be_nil
    end

    context "when running the read fails" do
      before do
        allow(mcp_client).to receive(:call_tool).with("get_coupon", {"code" => "SPRING"}).and_raise(Net::ReadTimeout)
      end

      it "runs it again on the next attempt without sending the batch or the write twice" do
        expect(service.call).to be_failure
        expect(write_call.reload.submitted_at).to be_present
        expect(ai_conversation.tool_calls.find_by!(tool_call_id: "call_next")).to have_attributes(status: "executing", submitted_at: nil)

        allow(mcp_client).to receive(:call_tool).with("get_coupon", {"code" => "SPRING"})
          .and_return({"content" => [{"type" => "text", "text" => "Coupon SPRING"}]})
        expect(described_class.new(ai_conversation:).call).to be_success

        expect(mcp_client).to have_received(:call_tool).with("create_coupon", anything).once
        expect(mistral_client).to have_received(:append_to_conversation).twice
        expect(ai_conversation.tool_calls.find_by!(tool_call_id: "call_next")).to have_attributes(status: "completed", result: "Coupon SPRING")
        expect(ai_conversation.reload.resuming_at).to be_nil
      end
    end

    context "when the model asks for another write" do
      let(:next_tool) { "create_coupon" }

      it "keeps it for the member's confirmation without running it" do
        expect(service.call).to be_success

        next_call = ai_conversation.tool_calls.find_by!(tool_call_id: "call_next")
        expect(next_call).to have_attributes(status: "pending", requires_confirmation: true, submitted_at: nil)
        expect(mcp_client).to have_received(:call_tool).once
        expect(mistral_client).to have_received(:append_to_conversation).once
        expect(LagoApiSchema.subscriptions).to have_received(:trigger).with(
          :ai_conversation_streamed,
          {id: ai_conversation.id},
          {chunk: nil, done: true, pending_tool_calls: [{id: next_call.id, name: "create_coupon", arguments: {"code" => "SPRING"}, status: "pending"}]}
        )
        expect(ai_conversation.reload.resuming_at).to be_nil
      end
    end

    context "when the member's role does not allow the next call" do
      let(:next_tool) { "delete_coupon" }

      it "sends the refusal without running it" do
        expect(service.call).to be_success

        next_call = ai_conversation.tool_calls.find_by!(tool_call_id: "call_next")
        expect(next_call).to have_attributes(status: "completed", submitted_at: be_present)
        expect(next_call.result).to include("coupons:delete")
        expect(mcp_client).not_to have_received(:call_tool).with("delete_coupon", anything)
      end
    end
  end

  context "when an earlier attempt stopped on new writes after keeping them" do
    let(:write_status) { "pending" }

    it "asks the member about them and ends the resume" do
      expect(service.call).to be_success

      expect(LagoMcpClient::Client).not_to have_received(:new)
      expect(mistral_client).not_to have_received(:append_to_conversation)
      expect(LagoApiSchema.subscriptions).to have_received(:trigger).with(
        :ai_conversation_streamed,
        {id: ai_conversation.id},
        {chunk: nil, done: true, pending_tool_calls: [{id: write_call.id, name: "create_coupon", arguments: {"coupon" => {"code" => "SPRING"}}, status: "pending"}]}
      )
      expect(ai_conversation.reload.resuming_at).to be_nil
    end
  end
end

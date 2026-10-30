# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConversations::StreamService do
  subject(:service) { described_class.new(ai_conversation:, message:) }

  let(:ai_conversation) { create(:ai_conversation, busy_at: Time.current) }
  let(:message) { "Hello, how are you?" }

  let(:mcp_client_mock) { instance_double(LagoMcpClient::Client) }
  let(:mistral_agent_mock) { instance_double(LagoMcpClient::Mistral::Agent) }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("LAGO_MCP_SERVER_URL").and_return("http://localhost:3001")

    allow(LagoMcpClient::Client).to receive(:new).and_return(mcp_client_mock)
    allow(LagoMcpClient::Mistral::Agent).to receive(:new).and_return(mistral_agent_mock)
    allow(LagoMcpClient::Config).to receive(:new).and_return(instance_double(LagoMcpClient::Config))

    allow(mcp_client_mock).to receive(:setup!)
    allow(mistral_agent_mock).to receive(:setup!)
    allow(mistral_agent_mock).to receive(:conversation_id).and_return(nil)
    allow(mistral_agent_mock).to receive(:pending_tool_calls).and_return(nil)
    allow(mistral_agent_mock).to receive(:awaiting_tool_results?).and_return(false)
    allow(LagoApiSchema.subscriptions).to receive(:trigger)
  end

  describe "#call" do
    context "when streaming succeeds" do
      before do
        allow(mistral_agent_mock).to receive(:chat)
      end

      it "takes the next message once the agent is done" do
        service.call

        expect(ai_conversation.reload).not_to be_busy
      end

      it "returns the ai_conversation" do
        result = service.call

        expect(result).to be_success
        expect(result.ai_conversation).to eq(ai_conversation)
      end

      it "streams chunks and notifies completion" do
        chunks = ["Hello", " ", "world", "!"]

        allow(mistral_agent_mock).to receive(:chat) do |_msg, &block|
          chunks.each { |chunk| block.call(chunk) }
        end

        service.call

        chunks.each do |chunk|
          expect(LagoApiSchema.subscriptions).to have_received(:trigger).with(
            :ai_conversation_streamed,
            {id: ai_conversation.id},
            {chunk:, done: false}
          )
        end

        expect(LagoApiSchema.subscriptions).to have_received(:trigger).with(
          :ai_conversation_streamed,
          {id: ai_conversation.id},
          {chunk: nil, done: true}
        )
      end

      it "ignores nil chunks" do
        allow(mistral_agent_mock).to receive(:chat) do |_msg, &block|
          block.call("text")
          block.call(nil)
          block.call("more")
        end

        service.call

        expect(LagoApiSchema.subscriptions).to have_received(:trigger).with(
          :ai_conversation_streamed,
          {id: ai_conversation.id},
          {chunk: "text", done: false}
        )

        expect(LagoApiSchema.subscriptions).to have_received(:trigger).with(
          :ai_conversation_streamed,
          {id: ai_conversation.id},
          {chunk: "more", done: false}
        )

        expect(LagoApiSchema.subscriptions).to have_received(:trigger).with(
          :ai_conversation_streamed,
          {id: ai_conversation.id},
          {chunk: nil, done: true}
        )
      end

      it "passes conversation_id to the mistral agent" do
        allow(mistral_agent_mock).to receive(:chat)

        service.call

        expect(LagoMcpClient::Mistral::Agent).to have_received(:new).with(
          client: mcp_client_mock,
          conversation_id: ai_conversation.mistral_conversation_id,
          tool_guard: an_instance_of(AiConversations::ToolGuard)
        )
      end

      context "when mistral agent returns a new conversation_id" do
        let(:ai_conversation) { create(:ai_conversation, mistral_conversation_id: nil) }
        let(:new_conversation_id) { "new-mistral-conv-456" }

        before do
          allow(mistral_agent_mock).to receive(:chat)
          allow(mistral_agent_mock).to receive(:conversation_id).and_return(new_conversation_id)
        end

        it "saves the conversation_id to the ai_conversation" do
          expect { service.call }.to change { ai_conversation.reload.mistral_conversation_id }
            .from(nil).to(new_conversation_id)
        end
      end

      context "when mistral agent returns the same conversation_id" do
        let(:existing_conversation_id) { "existing-conv-123" }
        let(:ai_conversation) { create(:ai_conversation, mistral_conversation_id: existing_conversation_id) }

        before do
          allow(mistral_agent_mock).to receive(:chat)
          allow(mistral_agent_mock).to receive(:conversation_id).and_return(existing_conversation_id)
        end

        it "does not update the ai_conversation" do
          allow(ai_conversation).to receive(:update!)
          service.call

          expect(ai_conversation).not_to have_received(:update!).with(hash_including(:mistral_conversation_id))
        end
      end
    end

    context "when the agent stops on writes to confirm" do
      before do
        allow(mistral_agent_mock).to receive(:chat)
        allow(mistral_agent_mock).to receive(:pending_tool_calls).and_return(
          results: [{tool_call_id: "call_read", name: "get_coupon", content: "Coupon SPRING"}],
          pending: [{tool_call_id: "call_write", name: "create_coupon", arguments: {"code" => "SPRING"}}]
        )
      end

      it "keeps every call of the batch for the member who owns the conversation" do
        expect { service.call }.to change(AiConversationToolCall, :count).by(2)

        completed = ai_conversation.tool_calls.find_by!(tool_call_id: "call_read")
        expect(completed).to have_attributes(
          name: "get_coupon",
          status: "completed",
          result: "Coupon SPRING",
          requires_confirmation: false,
          membership_id: ai_conversation.membership_id,
          organization_id: ai_conversation.organization_id,
          submitted_at: nil
        )

        pending = ai_conversation.tool_calls.find_by!(tool_call_id: "call_write")
        expect(pending).to have_attributes(
          name: "create_coupon",
          arguments: {"code" => "SPRING"},
          status: "pending",
          requires_confirmation: true,
          membership_id: ai_conversation.membership_id,
          position: 1
        )
      end

      it "takes the next message only once the pending calls are kept" do
        allow(ai_conversation).to receive(:update!).and_wrap_original do |original, **attributes|
          expect(ai_conversation.tool_calls.pending.count).to eq(1) if attributes.key?(:busy_at)
          original.call(**attributes)
        end

        service.call

        expect(ai_conversation.reload).not_to be_busy
      end

      it "sends the pending calls with the completion" do
        service.call

        pending = ai_conversation.tool_calls.pending.sole
        expect(LagoApiSchema.subscriptions).to have_received(:trigger).with(
          :ai_conversation_streamed,
          {id: ai_conversation.id},
          {
            chunk: nil,
            done: true,
            pending_tool_calls: [pending]
          }
        )
      end
    end

    context "when MCP server URL is missing" do
      before do
        allow(ENV).to receive(:[]).with("LAGO_MCP_SERVER_URL").and_return(nil)
      end

      it "returns forbidden_failure" do
        result = service.call

        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("feature_unavailable")
      end

      it "does not initialize clients" do
        service.call
        expect(LagoMcpClient::Client).not_to have_received(:new)
      end

      it "takes the next message" do
        service.call

        expect(ai_conversation.reload).not_to be_busy
      end
    end

    context "when an error occurs during streaming" do
      it "logs the error and sends it to frontend" do
        error = StandardError.new("Connection timeout")
        allow(mistral_agent_mock).to receive(:chat).and_raise(error)

        service.call

        expect(LagoApiSchema.subscriptions).to have_received(:trigger).with(
          :ai_conversation_streamed,
          {id: ai_conversation.id},
          {chunk: "Error: Connection timeout", done: true}
        )
      end

      it "takes the next message" do
        allow(mistral_agent_mock).to receive(:chat).and_raise(StandardError.new("Connection timeout"))

        service.call

        expect(ai_conversation.reload).not_to be_busy
      end

      context "when the model waits for the results of tool calls" do
        before { allow(mistral_agent_mock).to receive(:awaiting_tool_results?).and_return(true) }

        it "keeps the conversation closed, so no message reaches the model out of turn" do
          allow(mistral_agent_mock).to receive(:chat).and_raise(ActiveRecord::ConnectionNotEstablished)

          service.call

          expect(ai_conversation.reload).to be_busy
        end
      end

      it "returns service_failure result" do
        error = StandardError.new("Test error")
        allow(mistral_agent_mock).to receive(:chat).and_raise(error)

        result = service.call

        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq("stream_service_error")
      end
    end
  end
end

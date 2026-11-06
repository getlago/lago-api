# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConversations::DecideToolCallService do
  subject(:result) { described_class.call(tool_call:, confirmed:) }

  let(:ai_conversation) { create(:ai_conversation) }
  let(:tool_call) { create(:ai_conversation_tool_call, ai_conversation:) }
  let(:confirmed) { true }

  context "when the member confirms" do
    it "marks the call as confirmed and resumes the conversation" do
      freeze_time do
        expect(result).to be_success
        expect(tool_call.reload).to have_attributes(status: "confirmed", decided_at: Time.current, result: nil)
        expect(AiConversations::ResumeJob).to have_been_enqueued.with(ai_conversation)
        expect(ai_conversation.reload.resuming_at).to eq(Time.current)
      end
    end
  end

  context "when the member cancels" do
    let(:confirmed) { false }

    it "marks the call as cancelled with a result for the model" do
      expect(result).to be_success
      expect(tool_call.reload).to have_attributes(status: "cancelled", result: described_class::CANCELLED_RESULT)
      expect(AiConversations::ResumeJob).to have_been_enqueued.with(ai_conversation)
    end
  end

  context "when another write of the batch still waits" do
    before { create(:ai_conversation_tool_call, ai_conversation:) }

    it "does not resume the conversation yet" do
      expect(result).to be_success
      expect(ai_conversation.reload.resuming_at).to be_nil
      expect(AiConversations::ResumeJob).not_to have_been_enqueued
    end
  end

  context "when the call was already decided" do
    let(:tool_call) { create(:ai_conversation_tool_call, ai_conversation:, status: "cancelled") }

    it "returns a not allowed failure" do
      expect(result).to be_failure
      expect(result.error.code).to eq("tool_call_already_decided")
      expect(tool_call.reload).to be_cancelled
      expect(AiConversations::ResumeJob).not_to have_been_enqueued
    end
  end

  context "without a tool call" do
    let(:tool_call) { nil }

    it "returns a not found failure" do
      expect(result).to be_failure
      expect(result.error.error_code).to eq("ai_conversation_tool_call_not_found")
    end
  end
end

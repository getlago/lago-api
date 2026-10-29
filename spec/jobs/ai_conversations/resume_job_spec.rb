# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConversations::ResumeJob do
  let(:ai_conversation) { create(:ai_conversation) }

  it "calls the service" do
    allow(AiConversations::ResumeService).to receive(:call!)

    described_class.perform_now(ai_conversation)

    expect(AiConversations::ResumeService).to have_received(:call!).with(ai_conversation:, final_attempt: false)
  end

  context "when it is the last attempt" do
    it "lets the service tell the member about a failure" do
      allow(AiConversations::ResumeService).to receive(:call!)
      job = described_class.new(ai_conversation)
      job.executions = described_class::ATTEMPTS - 1

      job.perform_now

      expect(AiConversations::ResumeService).to have_received(:call!).with(ai_conversation:, final_attempt: true)
    end
  end

  context "when the conversation cannot resume" do
    before do
      allow(AiConversations::ResumeService).to receive(:call!)
        .and_raise(BaseService::ServiceFailure.new(BaseResult.new, code: "stream_service_error", error_message: "Mistral unavailable"))
    end

    it "retries the job" do
      expect { described_class.perform_now(ai_conversation) }.to have_enqueued_job(described_class).with(ai_conversation)
    end
  end
end

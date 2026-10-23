# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConversations::ResumeJob do
  let(:ai_conversation) { create(:ai_conversation) }

  before do
    allow(AiConversations::ResumeService).to receive(:call).with(ai_conversation:)
  end

  it "calls the service" do
    described_class.perform_now(ai_conversation:)

    expect(AiConversations::ResumeService).to have_received(:call)
  end
end

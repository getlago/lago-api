# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConversationToolCall do
  subject(:tool_call) { build(:ai_conversation_tool_call) }

  it { is_expected.to belong_to(:organization) }
  it { is_expected.to belong_to(:ai_conversation) }
  it { is_expected.to belong_to(:membership) }
  it { is_expected.to validate_presence_of(:tool_call_id) }
  it { is_expected.to validate_presence_of(:name) }

  describe ".unsubmitted" do
    it "returns the calls whose results were not sent to the model yet" do
      unsubmitted = create(:ai_conversation_tool_call)
      create(:ai_conversation_tool_call, status: "completed", submitted_at: Time.current)

      expect(described_class.unsubmitted).to eq([unsubmitted])
    end
  end
end

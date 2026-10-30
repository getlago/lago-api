# frozen_string_literal: true

RSpec.describe AiConversation do
  subject { build(:ai_conversation) }

  describe "associations" do
    it { is_expected.to belong_to(:membership) }
    it { is_expected.to belong_to(:organization) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
  end

  describe "#resuming?" do
    it "is true while a resume started within the timeout" do
      expect(build(:ai_conversation, resuming_at: 1.minute.ago)).to be_resuming
    end

    it "is false without a resume or once the timeout passed" do
      expect(build(:ai_conversation, resuming_at: nil)).not_to be_resuming
      expect(build(:ai_conversation, resuming_at: (described_class::RESUME_TIMEOUT + 1.minute).ago)).not_to be_resuming
    end
  end
end

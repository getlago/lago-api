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

  describe "#busy?" do
    it "is true while a resume started within the timeout" do
      expect(build(:ai_conversation, busy_at: 1.minute.ago)).to be_busy
    end

    it "is false without a resume or once the timeout passed" do
      expect(build(:ai_conversation, busy_at: nil)).not_to be_busy
      expect(build(:ai_conversation, busy_at: (described_class::BUSY_TIMEOUT + 1.minute).ago)).not_to be_busy
    end
  end
end

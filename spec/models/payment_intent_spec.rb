# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentIntent, type: :model do
  let(:payment_intent) { create(:payment_intent) }

  it { is_expected.to belong_to(:invoice) }

  it { is_expected.to validate_presence_of(:status) }
  it { is_expected.to validate_presence_of(:expires_at) }

  describe ".active" do
    subject { described_class.active }

    let!(:scoped) { create(:payment_intent) }

    before { create(:payment_intent, :expired) }

    it "returns intents with future expire date" do
      expect(subject).to contain_exactly scoped
    end
  end

  describe ".awaiting_expiration" do
    subject { described_class.awaiting_expiration }

    let!(:scoped) { create(:payment_intent, expires_at: generate(:past_date)) }

    before do
      create(:payment_intent)
      create(:payment_intent, :expired)
    end

    it "returns intents with past expire date and active status" do
      expect(subject).to contain_exactly scoped
    end
  end
end

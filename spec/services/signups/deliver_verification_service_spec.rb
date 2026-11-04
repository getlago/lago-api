# frozen_string_literal: true

require "rails_helper"

RSpec.describe Signups::DeliverVerificationService do
  subject(:result) { described_class.call(pending_signup:) }

  let(:pending_signup) { create(:pending_signup, email: "Jane@GetLago.com") }

  before { freeze_time }

  context "with a new address" do
    it "emails a link whose token is the attempt's only live link" do
      expect { result }.to change { ActionMailer::Base.deliveries.count }.by(1)

      token = ActionMailer::Base.deliveries.last.body.encoded[%r{/verify-email\?token=([A-Za-z0-9_-]{43})}, 1]
      expect(pending_signup.tokens.pending.sole).to have_attributes(
        token_digest: PendingSignupToken.digest(token),
        expires_at: 24.hours.from_now
      )
    end

    it "replaces the attempt's previous link and leaves other attempts alone" do
      previous = create(:pending_signup_token, pending_signup:)
      other = create(:pending_signup_token, pending_signup: create(:pending_signup, email: "jane@getlago.com"))

      result

      expect(previous.reload).to be_replaced
      expect(other.reload).to be_pending
    end
  end

  context "when the address already has a user, whatever its case" do
    before { create(:user, email: "jane@getlago.com") }

    it "emails that an account exists, issues no link and keeps no password" do
      result

      expect(ActionMailer::Base.deliveries.last.subject).to eq("You already have a Lago account")
      expect(pending_signup.tokens).to be_empty
      expect(pending_signup.reload).to have_attributes(password_digest: nil, closed_at: Time.current)
    end
  end

  context "when the attempt is verified" do
    let(:pending_signup) { create(:pending_signup, :verified) }

    it "sends nothing" do
      expect { result }.not_to change { ActionMailer::Base.deliveries.count }
      expect(pending_signup.tokens).to be_empty
    end
  end

  context "when the delivery runs after the attempt's window, within a day" do
    let(:pending_signup) { create(:pending_signup, expires_at: 1.hour.ago) }

    it "still sends a link, which ends a day after that window" do
      expect { result }.to change { ActionMailer::Base.deliveries.count }.by(1)
      expect(pending_signup.tokens.pending.sole.expires_at).to eq(1.hour.ago + 24.hours)
    end
  end

  context "when the delivery runs a day after the attempt's window" do
    let(:pending_signup) { create(:pending_signup, expires_at: 24.hours.ago) }

    it "sends nothing and issues no link" do
      expect { result }.not_to change { ActionMailer::Base.deliveries.count }
      expect(pending_signup.tokens).to be_empty
    end
  end

  context "when the attempt was closed and the address has no user" do
    let(:pending_signup) { create(:pending_signup, :closed) }

    it "sends nothing" do
      expect { result }.not_to change { ActionMailer::Base.deliveries.count }
    end
  end

  context "when delivery fails" do
    before do
      allow_any_instance_of(Mail::Message).to receive(:deliver).and_raise(Net::OpenTimeout) # rubocop:disable RSpec/AnyInstance
    end

    it "keeps the issued link, since it was committed before sending" do
      expect { result }.to raise_error(Net::OpenTimeout)
      expect(pending_signup.tokens.pending.count).to eq(1)
    end
  end
end

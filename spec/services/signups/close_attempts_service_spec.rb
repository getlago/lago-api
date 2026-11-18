# frozen_string_literal: true

require "rails_helper"

RSpec.describe Signups::CloseAttemptsService do
  subject(:result) { described_class.call(normalized_email: "jane@getlago.com", except:) }

  let(:except) { nil }
  let(:open_attempt) { create(:pending_signup, email: "Jane@GetLago.com") }
  let!(:open_token) { create(:pending_signup_token, pending_signup: open_attempt) }

  before { freeze_time }

  it "closes the open attempts of the address and stops their links" do
    result

    expect(open_attempt.reload).to have_attributes(password_digest: nil, closed_at: Time.current, verified_at: nil, user_id: nil)
    expect(open_token.reload).to be_replaced
  end

  it "leaves verified attempts, other addresses and +tag variants alone" do
    verified = create(:pending_signup, :verified, email: "jane@getlago.com")
    tagged = create(:pending_signup, email: "jane+x@getlago.com")
    tagged_token = create(:pending_signup_token, pending_signup: tagged)

    expect { result }.not_to change { [verified.reload.attributes, tagged.reload.attributes] }
    expect(tagged_token.reload).to be_pending
  end

  context "with an excepted attempt" do
    let(:except) { open_attempt }

    it "leaves it open" do
      result

      expect(open_attempt.reload.closed_at).to be_nil
      expect(open_token.reload).to be_pending
    end
  end

  it "never makes a closed attempt's secret usable" do
    signup_secret = PendingSignup.generate_signup_secret
    closed = create(:pending_signup, email: "jane@getlago.com", signup_secret:)
    create(:user, email: "jane@getlago.com")

    result

    expect(Signups::StatusService.call(signup_secret:).status).to eq(:pending)
    expect(Signups::ExchangeSecretService.call(signup_secret:).error.code).to eq("email_not_verified")
    expect(closed.reload.verified_at).to be_nil
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::GoogleOauthState do
  let(:issued) { described_class.issue }

  describe ".issue" do
    it "returns a signed state, a secret and a PKCE code verifier, and the state reveals neither" do
      expect(issued.state).to match(/\A\d+\.\h{64}\z/)
      expect(issued.secret).to match(/\A[A-Za-z0-9_-]{43}\z/)
      expect(issued.code_verifier).to match(/\A[A-Za-z0-9_-]{43}\z/)
      expect(issued.state).not_to include(issued.secret, issued.code_verifier)
    end
  end

  describe ".verify" do
    it "returns the code verifier of the flow for its own secret" do
      expect(described_class.verify(state: issued.state, secret: issued.secret)).to eq(issued.code_verifier)
    end

    it "refuses another secret, an altered timestamp or an altered signature" do
      issued_at, signature = issued.state.split(".")

      expect(described_class.verify(state: issued.state, secret: described_class.issue.secret)).to be_nil
      expect(described_class.verify(state: "#{issued_at.to_i - 1}.#{signature}", secret: issued.secret)).to be_nil
      expect(described_class.verify(state: "#{issued_at}.#{signature.reverse}", secret: issued.secret)).to be_nil
    end

    it "refuses malformed values" do
      [
        {state: nil, secret: issued.secret}, {state: issued.state, secret: ""},
        {state: "1" * 129, secret: issued.secret}, {state: issued.state, secret: "a" * 129},
        {state: "nodot", secret: issued.secret}, {state: "abc.#{"0" * 64}", secret: issued.secret}
      ].each do |input|
        expect(described_class.verify(**input)).to be_nil
      end
    end

    it "expires after 10 minutes and refuses a state from the future" do
      state = issued.state

      travel_to(10.minutes.from_now + 1.second) { expect(described_class.verify(state:, secret: issued.secret)).to be_nil }
      travel_to(2.minutes.ago) { expect(described_class.verify(state:, secret: issued.secret)).to be_nil }
    end

    it "refuses a state issued for another region" do
      allow(Rails.application.config).to receive(:lago_front_url).and_return("https://app.getlago.com")
      state = described_class.issue

      allow(Rails.application.config).to receive(:lago_front_url).and_return("https://app.eu.getlago.com")

      expect(described_class.verify(state: state.state, secret: state.secret)).to be_nil
    end
  end
end

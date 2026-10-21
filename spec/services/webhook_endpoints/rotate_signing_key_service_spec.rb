# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookEndpoints::RotateSigningKeyService do
  subject(:result) { described_class.call(webhook_endpoint:, grace_period:) }

  let(:webhook_endpoint) { create(:webhook_endpoint, signature_algo: :standard_webhooks) }
  let(:grace_period) { 24.hours }
  let(:previous_key) { webhook_endpoint.signing_keys.sole }

  it "creates a new signing key" do
    expect { result }.to change { webhook_endpoint.signing_keys.count }.from(1).to(2)
    expect(result.signing_key).to be_present
    expect(result.signing_key.expires_at).to be_nil
  end

  it "keeps the previous key usable until the grace period passes" do
    previous = previous_key
    result

    expect(previous.reload.expires_at).to be_within(1.minute).of(grace_period.from_now)
    expect(webhook_endpoint.signing_keys.usable).to match_array([previous, result.signing_key])
  end

  context "when the grace period has passed" do
    it "no longer counts the previous key as usable" do
      previous = previous_key
      result

      travel_to(grace_period.from_now + 1.minute) do
        expect(webhook_endpoint.signing_keys.usable).to eq([result.signing_key])
        expect(previous.reload).to be_present
      end
    end
  end
end

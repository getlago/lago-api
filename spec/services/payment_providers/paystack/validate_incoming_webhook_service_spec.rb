# frozen_string_literal: true

require "rails_helper"
require "openssl"

RSpec.describe PaymentProviders::Paystack::ValidateIncomingWebhookService do
  subject(:result) { described_class.call(payload:, signature:, payment_provider:) }

  let(:payload) { {event: "charge.success", data: {reference: "ref_123"}}.to_json }
  let(:secret_key) { "sk_test_#{SecureRandom.hex(16)}" }
  let(:payment_provider) { create(:paystack_provider, secret_key:) }
  let(:signature) { OpenSSL::HMAC.hexdigest("SHA512", secret_key, payload) }

  it "returns success when the signature is valid" do
    expect(result).to be_success
  end

  context "when signature is missing" do
    let(:signature) { nil }

    it "returns a service failure" do
      expect(result).not_to be_success
      expect(result.error.code).to eq("webhook_error")
      expect(result.error.error_message).to eq("Missing signature")
    end
  end

  context "when signature is invalid" do
    let(:signature) { "invalid" }

    it "returns a service failure" do
      expect(result).not_to be_success
      expect(result.error.code).to eq("webhook_error")
      expect(result.error.error_message).to eq("Invalid signature")
    end
  end

  context "when payload is invalid JSON" do
    let(:payload) { "not-json" }
    let(:signature) { OpenSSL::HMAC.hexdigest("SHA512", secret_key, payload) }

    it "returns a service failure" do
      expect(result).not_to be_success
      expect(result.error.code).to eq("webhook_error")
      expect(result.error.error_message).to eq("Invalid payload")
    end
  end
end

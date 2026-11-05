# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookEndpointSigningKey do
  subject(:signing_key) { build(:webhook_endpoint_signing_key) }

  describe "associations" do
    it do
      expect(signing_key).to belong_to(:organization)
      expect(signing_key).to belong_to(:webhook_endpoint)
    end
  end

  describe "Scopes" do
    describe ".usable" do
      let(:webhook_endpoint) { create(:webhook_endpoint) }
      let(:non_expiring) { create(:webhook_endpoint_signing_key, webhook_endpoint:) }
      let(:not_expired) { create(:webhook_endpoint_signing_key, webhook_endpoint:, expires_at: 1.minute.from_now) }

      before do
        freeze_time

        non_expiring
        not_expired
        create(:webhook_endpoint_signing_key, webhook_endpoint:, expires_at: 1.minute.ago)
        create(:webhook_endpoint_signing_key, webhook_endpoint:, expires_at: Time.current)
      end

      it "returns the keys that never expire or expire in the future" do
        expect(described_class.usable).to match_array([non_expiring, not_expired])
      end
    end
  end

  describe "validations" do
    it do
      expect(signing_key).to validate_presence_of(:secret_key).on(:update)
    end
  end

  describe "secret generation" do
    let(:signing_key) { create(:webhook_endpoint_signing_key) }

    it "generates a whsec_ secret of 24 random bytes" do
      expect(signing_key.secret_key).to match(/\Awhsec_[A-Za-z0-9+\/=]+\z/)
      expect(Base64.strict_decode64(signing_key.secret_key.delete_prefix("whsec_")).bytesize).to eq(24)
    end

    it "generates a different secret for each key" do
      other_key = create(:webhook_endpoint_signing_key, webhook_endpoint: signing_key.webhook_endpoint)

      expect(other_key.secret_key).not_to eq(signing_key.secret_key)
    end

    context "when a secret is given" do
      let(:signing_key) { create(:webhook_endpoint_signing_key, secret_key: "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw") }

      it "keeps it" do
        expect(signing_key.reload.secret_key).to eq("whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw")
      end
    end
  end

  describe "encryption" do
    let(:signing_key) { create(:webhook_endpoint_signing_key) }

    it "keeps the secret encrypted at rest" do
      secret = signing_key.secret_key

      expect(signing_key.reload.secret_key).to eq(secret)
      expect(signing_key.ciphertext_for(:secret_key)).not_to include(secret)
    end
  end

  describe "#sign" do
    subject(:signing_key) { build(:webhook_endpoint_signing_key, secret_key: "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw") }

    # Test vector of the Standard Webhooks reference libraries.
    let(:content) { 'msg_p5jXN8AQM9LWM0D4loKWxJek.1614265330.{"test": 2432232314}' }

    it "returns the base64 HMAC-SHA256 of the content keyed with the decoded secret" do
      expect(signing_key.sign(content)).to eq("g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=")
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookEndpointSigningKey do
  subject(:signing_key) { create(:webhook_endpoint_signing_key) }

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:webhook_endpoint)
    end
  end

  describe "validations" do
    it do
      expect(subject).to validate_presence_of(:secret)
    end
  end

  describe "Scopes" do
    let(:webhook_endpoint) { create(:webhook_endpoint) }
    let!(:active) { create(:webhook_endpoint_signing_key, webhook_endpoint:) }
    let!(:expiring) { create(:webhook_endpoint_signing_key, :expiring, webhook_endpoint:) }
    let!(:expired) { create(:webhook_endpoint_signing_key, :expired, webhook_endpoint:) }

    describe ".usable" do
      it "returns keys with no or a future expiry" do
        expect(described_class.usable).to match_array([active, expiring])
      end
    end

    describe ".expired" do
      it "returns keys past their expiry" do
        expect(described_class.expired).to eq([expired])
      end
    end
  end

  describe "#generate_secret" do
    it "generates a whsec_ prefixed secret of 24 random bytes" do
      raw = signing_key.secret.delete_prefix("whsec_")
      expect(signing_key.secret).to start_with("whsec_")
      expect(Base64.strict_decode64(raw).bytesize).to eq(24)
    end

    it "stores the secret encrypted at rest" do
      ciphertext = described_class.connection.select_value(
        "SELECT secret FROM webhook_endpoint_signing_keys WHERE id = '#{signing_key.id}'"
      )
      expect(ciphertext).not_to eq(signing_key.secret)
    end
  end

  describe "#sign" do
    it "produces the HMAC-SHA256 digest of the content under the secret" do
      key = Base64.strict_decode64(signing_key.secret.delete_prefix("whsec_"))
      expected = OpenSSL::HMAC.digest("SHA256", key, "a.b.c")

      expect(signing_key.sign("a.b.c")).to eq(expected)
    end
  end
end

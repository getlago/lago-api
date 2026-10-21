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
      expect(subject).to validate_presence_of(:private_key)
      expect(subject).to validate_presence_of(:public_key)
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

  describe "#generate_key_pair" do
    it "generates a whsk_ prefixed ed25519 private key" do
      raw = signing_key.private_key.delete_prefix("whsk_")
      expect(signing_key.private_key).to start_with("whsk_")
      expect(Base64.strict_decode64(raw).bytesize).to eq(32)
    end

    it "generates a whpk_ prefixed ed25519 public key" do
      raw = signing_key.public_key.delete_prefix("whpk_")
      expect(signing_key.public_key).to start_with("whpk_")
      expect(Base64.strict_decode64(raw).bytesize).to eq(32)
    end

    it "stores the private key encrypted at rest" do
      ciphertext = described_class.connection.select_value(
        "SELECT private_key FROM webhook_endpoint_signing_keys WHERE id = '#{signing_key.id}'"
      )
      expect(ciphertext).not_to eq(signing_key.private_key)
    end
  end

  describe "#sign" do
    it "produces a signature the matching public key verifies" do
      raw_public = Base64.strict_decode64(signing_key.public_key.delete_prefix("whpk_"))
      public_key = OpenSSL::PKey.new_raw_public_key("ED25519", raw_public)

      expect(public_key.verify(nil, signing_key.sign("a.b.c"), "a.b.c")).to be(true)
    end
  end
end

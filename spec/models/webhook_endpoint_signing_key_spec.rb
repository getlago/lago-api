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

  describe "validations" do
    it { expect(signing_key).to be_valid }

    describe "secret validation" do
      subject(:signing_key) { create(:webhook_endpoint_signing_key) }

      before { signing_key.secret = nil }

      it "requires a secret once the key exists" do
        expect(signing_key).not_to be_valid
        expect(signing_key.errors.where(:secret, :blank)).to be_present
      end
    end

    describe "organization validation" do
      subject(:signing_key) { build(:webhook_endpoint_signing_key, webhook_endpoint:, organization:) }

      let(:webhook_endpoint) { create(:webhook_endpoint) }
      let(:organization) { webhook_endpoint.organization }

      before { signing_key.valid? }

      it { expect(signing_key.errors.where(:organization)).to be_empty }

      context "with an organization other than the endpoint's" do
        let(:organization) { create(:organization) }

        it { expect(signing_key.errors.messages[:organization]).to eq(["must_belong_to_same_organization"]) }
      end

      context "without an endpoint" do
        let(:webhook_endpoint) { nil }
        let(:organization) { create(:organization) }

        it "only reports the missing endpoint" do
          expect(signing_key.errors.where(:organization)).to be_empty
          expect(signing_key.errors.where(:webhook_endpoint, :blank)).to be_present
        end
      end
    end
  end

  describe "secret" do
    subject(:signing_key) { create(:webhook_endpoint_signing_key) }

    it "generates a whsec_ secret holding 32 random bytes" do
      expect(signing_key.secret).to match(/\Awhsec_[A-Za-z0-9+\/]{43}=\z/)
      expect(signing_key.signing_secret.bytesize).to eq(32)
    end

    it "generates a different secret for each key" do
      expect(signing_key.secret).not_to eq(create(:webhook_endpoint_signing_key).secret)
    end

    it "stores the secret encrypted" do
      raw = described_class.connection.select_value(
        described_class.where(id: signing_key.id).select(:secret).to_sql
      )

      expect(raw).not_to include(signing_key.secret)
      expect(signing_key.ciphertext_for(:secret)).to eq(raw)
      expect(described_class.find(signing_key.id).secret).to eq(signing_key.secret)
    end

    context "with an explicit secret" do
      subject(:signing_key) { create(:webhook_endpoint_signing_key, secret:) }

      let(:secret) { "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw" }

      it "keeps it" do
        expect(signing_key.reload.secret).to eq(secret)
      end
    end
  end

  describe "#signing_secret" do
    subject(:signing_key) { build(:webhook_endpoint_signing_key, secret: "whsec_#{Base64.strict_encode64("0123456789abcdef0123456789abcdef")}") }

    it "returns the decoded bytes without the prefix" do
      expect(signing_key.signing_secret).to eq("0123456789abcdef0123456789abcdef")
    end
  end
end

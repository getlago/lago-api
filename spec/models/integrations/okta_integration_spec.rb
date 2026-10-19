# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::OktaIntegration do
  subject(:okta_integration) { build(:okta_integration) }

  it { is_expected.to validate_presence_of(:domain) }
  it { is_expected.to validate_presence_of(:organization_name) }
  it { is_expected.to validate_presence_of(:client_id) }
  it { is_expected.to validate_presence_of(:client_secret) }

  describe "#host" do
    context "when settings host is present" do
      before do
        subject.host = "test.com"
      end

      it "use the settings host" do
        expect(subject.host).to eq("test.com")
      end
    end

    context "when settings host is nil" do
      before do
        subject.organization_name = "test"
        subject.host = nil
      end

      it "use the default host" do
        expect(subject.host).to eq("test.okta.com")
      end
    end
  end

  describe "#sso_issuer" do
    it "returns the downcased host" do
      okta_integration.host = "Acme.Okta.com"

      expect(okta_integration.sso_issuer).to eq("acme.okta.com")
    end
  end

  describe "validations" do
    describe "host validation" do
      it "accepts a bare hostname" do
        okta_integration.host = "acme.okta-emea.com"

        expect(okta_integration).to be_valid
      end

      ["evil.com/", "evil.com?", "evil.com#", "user@evil.com", "evil.com:8443", "evil .com", "-evil.com"].each do |host|
        it "rejects #{host.inspect}" do
          okta_integration.host = host

          expect(okta_integration).not_to be_valid
          expect(okta_integration.errors[:host]).to eq(["host_invalid"])
        end
      end

      context "when an existing integration already stores an invalid host" do
        subject(:okta_integration) { create(:okta_integration) }

        before do
          settings = okta_integration.settings.merge("host" => "legacy.example.com/okta")
          okta_integration.update_column(:settings, settings) # rubocop:disable Rails/SkipsModelValidations
          okta_integration.reload
        end

        it "keeps saving other changes" do
          okta_integration.client_id = "new_client_id"

          expect(okta_integration).to be_valid
        end

        it "rejects a new invalid host" do
          okta_integration.host = "other.example.com/okta"

          expect(okta_integration).not_to be_valid
        end
      end
    end

    describe "organization_name validation" do
      it "rejects a name that does not build a bare hostname" do
        okta_integration.organization_name = "evil.com/x?"

        expect(okta_integration).not_to be_valid
        expect(okta_integration.errors[:organization_name]).to eq(["organization_name_invalid"])
      end

      it "ignores the name when the host is set" do
        okta_integration.organization_name = "Acme Corp"
        okta_integration.host = "acme.okta.com"

        expect(okta_integration).to be_valid
      end

      context "when the host of an existing integration is cleared" do
        subject(:okta_integration) { create(:okta_integration, settings: {client_id: "id", domain: "acme.test", organization_name: "Acme Corp", host: "acme.okta.com"}) }

        it "rejects a name that does not build a bare hostname" do
          okta_integration.host = nil

          expect(okta_integration).not_to be_valid
          expect(okta_integration.errors[:organization_name]).to eq(["organization_name_invalid"])
        end
      end

      context "when an existing integration already stores an invalid name" do
        subject(:okta_integration) { create(:okta_integration) }

        before do
          settings = okta_integration.settings.merge("organization_name" => "legacy name")
          okta_integration.update_column(:settings, settings) # rubocop:disable Rails/SkipsModelValidations
          okta_integration.reload
        end

        it "keeps saving other changes" do
          okta_integration.client_id = "new_client_id"

          expect(okta_integration).to be_valid
        end
      end
    end

    it "validates uniqueness of domain" do
      expect(okta_integration).to be_valid
    end

    context "when domain already exists" do
      before { create(:okta_integration) }

      it "does not validate the record" do
        expect(okta_integration).not_to be_valid
        expect(okta_integration.errors).to include(:domain)
      end
    end
  end
end

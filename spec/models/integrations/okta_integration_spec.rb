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

    context "when settings host is blank" do
      before do
        subject.organization_name = "test"
        subject.host = ""
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

    context "when domain already exists with another Okta org" do
      before { create(:okta_integration, organization_name: "other") }

      it "does not validate the record" do
        expect(okta_integration).not_to be_valid
        expect(okta_integration.errors.details[:domain]).to include(error: "domain_not_unique")
      end
    end

    context "when domain already exists with the same Okta org" do
      before { create(:okta_integration, host: "Login.Foobar.test") }

      it "accepts the shared domain" do
        okta_integration.host = "login.foobar.test"

        expect(okta_integration).to be_valid
      end

      it "refuses moving the shared domain to another host" do
        okta_integration.host = "login.foobar.test"
        okta_integration.save!
        okta_integration.host = "evil.test"

        expect(okta_integration).not_to be_valid
        expect(okta_integration.errors.details[:domain]).to include(error: "domain_not_unique")
      end
    end
  end

  describe ".for_login" do
    let(:email) { "user@foo.test" }
    let(:first_integration) { create(:okta_integration, created_at: 2.days.ago) }
    let(:second_integration) { create(:okta_integration, created_at: 1.day.ago) }

    before do
      first_integration
      second_integration
    end

    it "returns nil when no integration claims the domain" do
      expect(described_class.for_login(email: "user@other.test")).to be_nil
    end

    it "returns the oldest integration when the user belongs to none of their organizations" do
      expect(described_class.for_login(email:)).to eq(first_integration)
    end

    it "returns the integration of an organization the user is an active member of" do
      create(:membership, user: create(:user, email:), organization: second_integration.organization)

      expect(described_class.for_login(email:)).to eq(second_integration)
    end

    it "ignores revoked memberships" do
      create(:membership, :revoked, user: create(:user, email:), organization: second_integration.organization)

      expect(described_class.for_login(email:)).to eq(first_integration)
    end

    context "when the oldest member organization does not allow Okta" do
      let(:first_integration) do
        create(:okta_integration, created_at: 2.days.ago,
          organization: create(:organization, authentication_methods: %w[email_password]))
      end
      let(:second_integration) do
        create(:okta_integration, created_at: 1.day.ago,
          organization: create(:organization, authentication_methods: %w[email_password okta]))
      end

      before do
        user = create(:user, email:)
        create(:membership, user:, organization: first_integration.organization)
        create(:membership, user:, organization: second_integration.organization)
      end

      it "returns the integration of the member organization that allows it" do
        expect(described_class.for_login(email:)).to eq(second_integration)
      end
    end

    it "returns the integration of the invite's organization first" do
      create(:membership, user: create(:user, email:), organization: first_integration.organization)

      expect(described_class.for_login(email:, organization_id: second_integration.organization_id)).to eq(second_integration)
    end
  end
end

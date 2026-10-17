# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::EntraIdIntegration do
  subject(:entra_id_integration) { build(:entra_id_integration) }

  it { is_expected.to validate_presence_of(:domain) }
  it { is_expected.to validate_presence_of(:tenant_id) }
  it { is_expected.to validate_presence_of(:client_id) }
  it { is_expected.to validate_presence_of(:client_secret) }

  describe "#host" do
    context "when settings host is present" do
      before do
        subject.host = "login.microsoftonline.us"
      end

      it "use the settings host" do
        expect(subject.host).to eq("login.microsoftonline.us")
      end
    end

    context "when settings host is nil" do
      before do
        subject.host = nil
      end

      it "use the default host" do
        expect(subject.host).to eq("login.microsoftonline.com")
      end
    end
  end

  describe "Scopes" do
    describe ".with_domain" do
      let!(:integration) { create(:entra_id_integration, domain: "bosch.com", additional_domains: ["de.bosch.com"]) }

      before { create(:entra_id_integration, domain: "other.test") }

      it "matches the primary domain case-insensitively" do
        expect(described_class.with_domain("Bosch.COM")).to eq([integration])
      end

      it "matches an additional domain case-insensitively" do
        expect(described_class.with_domain("DE.bosch.com")).to eq([integration])
      end

      it "does not match a parent or child domain that is not listed" do
        expect(described_class.with_domain("fr.bosch.com")).to be_empty
        expect(described_class.with_domain("bosch")).to be_empty
      end
    end
  end

  describe "#additional_domains" do
    it "defaults to an empty list" do
      expect(build(:entra_id_integration).additional_domains).to eq([])
    end

    it "strips, downcases, drops blanks and duplicates" do
      subject.additional_domains = [" DE.Bosch.com ", "de.bosch.com", "", nil, "us.bosch.com"]

      expect(subject.additional_domains).to eq(["de.bosch.com", "us.bosch.com"])
    end
  end

  describe "#domains" do
    it "returns the primary domain followed by the additional domains" do
      subject.domain = "Bosch.com"
      subject.additional_domains = ["de.bosch.com", "bosch.com"]

      expect(subject.domains).to eq(["bosch.com", "de.bosch.com"])
    end
  end

  describe "validations" do
    it "validates uniqueness of domain" do
      expect(entra_id_integration).to be_valid
    end

    context "when domain already exists" do
      before { create(:entra_id_integration) }

      it "does not validate the record" do
        expect(entra_id_integration).not_to be_valid
        expect(entra_id_integration.errors).to include(:domain)
      end
    end

    context "when the domain is an additional domain of another integration" do
      subject(:entra_id_integration) { build(:entra_id_integration, domain: "de.bosch.com") }

      before { create(:entra_id_integration, domain: "bosch.com", additional_domains: ["de.bosch.com"]) }

      it "is invalid" do
        expect(entra_id_integration).not_to be_valid
        expect(entra_id_integration.errors.details[:domain]).to include(error: "domain_not_unique")
      end
    end

    context "when an additional domain is claimed by another integration" do
      subject(:entra_id_integration) { build(:entra_id_integration, domain: "bosch.com", additional_domains: ["De.Other.test"]) }

      before { create(:entra_id_integration, domain: "de.other.test") }

      it "is invalid" do
        expect(entra_id_integration).not_to be_valid
        expect(entra_id_integration.errors.details[:additional_domains]).to include(error: "domain_not_unique")
      end
    end

    context "when legacy integrations have primary domains that differ only by casing" do
      let!(:legacy_integration) { build(:entra_id_integration, domain: "Example.com").tap { it.save!(validate: false) } }

      before { build(:entra_id_integration, domain: "example.com").save!(validate: false) }

      it "still saves unrelated changes" do
        legacy_integration.host = "login.microsoftonline.us"

        expect(legacy_integration).to be_valid
      end

      it "still saves a change that only alters the domain casing" do
        legacy_integration.domain = "EXAMPLE.com"

        expect(legacy_integration).to be_valid
      end

      it "rejects a newly claimed additional domain held by another integration" do
        other = create(:entra_id_integration, domain: "other.test")
        legacy_integration.additional_domains = [other.domain]

        expect(legacy_integration).not_to be_valid
        expect(legacy_integration.errors.details[:additional_domains]).to include(error: "domain_not_unique")
      end
    end

    context "when an existing integration moves to a domain held by another integration" do
      subject(:entra_id_integration) { create(:entra_id_integration, domain: "mine.test") }

      before { create(:entra_id_integration, domain: "Taken.test") }

      it "is invalid" do
        entra_id_integration.domain = "taken.test"

        expect(entra_id_integration).not_to be_valid
        expect(entra_id_integration.errors.details[:domain]).to include(error: "domain_not_unique")
      end
    end

    context "when an additional domain repeats the integration's own primary domain" do
      subject(:entra_id_integration) { create(:entra_id_integration, domain: "bosch.com") }

      before { entra_id_integration.additional_domains = ["bosch.com", "de.bosch.com"] }

      it "is valid" do
        expect(entra_id_integration).to be_valid
      end
    end

    context "when an additional domain has an invalid format" do
      %w[com localhost bosch..com -bosch.com bosch.com/path *.bosch.com].each do |invalid_domain|
        it "rejects #{invalid_domain}" do
          subject.additional_domains = ["de.bosch.com", invalid_domain]

          expect(subject).not_to be_valid
          expect(subject.errors.details[:additional_domains]).to include(error: "invalid_format")
        end
      end
    end

    context "when tenant_id contains unsafe URL characters" do
      before { subject.tenant_id = "bad/tenant" }

      it "is invalid" do
        expect(subject).not_to be_valid
        expect(subject.errors).to include(:tenant_id)
      end
    end

    context "when host contains unsafe URL characters" do
      before { subject.host = "evil.com/path" }

      it "is invalid" do
        expect(subject).not_to be_valid
        expect(subject.errors).to include(:host)
      end
    end
  end
end

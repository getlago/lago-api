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
  end
end

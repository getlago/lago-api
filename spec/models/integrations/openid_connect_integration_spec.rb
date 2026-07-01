# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::OpenidConnectIntegration do
  subject(:openid_connect_integration) { build(:openid_connect_integration) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:domain) }
    it { is_expected.to validate_presence_of(:issuer) }
    it { is_expected.to validate_presence_of(:client_id) }
    it { is_expected.to validate_presence_of(:client_secret) }

    it "validates uniqueness of domain" do
      expect(openid_connect_integration).to be_valid
    end

    context "when domain already exists" do
      before { create(:openid_connect_integration) }

      it "does not validate the record" do
        expect(openid_connect_integration).not_to be_valid
        expect(openid_connect_integration.errors).to include(:domain)
      end
    end
  end
end

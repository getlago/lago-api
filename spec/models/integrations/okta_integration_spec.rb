# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::OktaIntegration do
  subject(:okta_integration) { build(:okta_integration) }

  it { is_expected.to validate_presence_of(:domain) }
  it { is_expected.to validate_presence_of(:organization_name) }
  it { is_expected.to validate_presence_of(:client_id) }
  it { is_expected.to validate_presence_of(:client_secret) }

  describe "validations" do
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

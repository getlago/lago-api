# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::AgentStorefrontIntegration do
  subject(:integration) { build(:agent_storefront_integration, organization:) }

  let_it_be(:organization) { create_default(:organization) }

  describe "validations" do
    it do
      expect(subject).to validate_presence_of(:code)
      expect(subject).to validate_presence_of(:name)
      expect(subject).to validate_presence_of(:payment_provider_code)
      expect(subject).to validate_presence_of(:scope)
    end

    it "validates uniqueness of the code" do
      expect(integration).to validate_uniqueness_of(:code).scoped_to(:organization_id)
    end

    describe "payment_provider_code validation" do
      context "when no stripe connection has the code" do
        before { integration.payment_provider_code = "unknown" }

        it "is invalid" do
          expect(integration).not_to be_valid
          expect(integration.errors.messages[:payment_provider_code]).to eq(["payment_provider_not_found"])
        end
      end

      context "when the stripe connection belongs to another organization" do
        let(:other_provider) { create(:stripe_provider, organization: create(:organization)) }

        before { integration.payment_provider_code = other_provider.code }

        it "is invalid" do
          expect(integration).not_to be_valid
          expect(integration.errors.messages[:payment_provider_code]).to eq(["payment_provider_not_found"])
        end
      end

      context "when the stripe connection is discarded" do
        before { integration.stripe_provider.discard! }

        it "is invalid" do
          expect(integration).not_to be_valid
          expect(integration.errors.messages[:payment_provider_code]).to eq(["payment_provider_not_found"])
        end
      end
    end

    describe "resource urls validation" do
      it "accepts https urls and blank values" do
        integration.resource_endpoint = "https://api.acme.example/v1"
        integration.resource_instructions = nil
        expect(integration).to be_valid

        integration.resource_instructions = ""
        expect(integration).to be_valid
      end

      it "refuses http urls" do
        integration.resource_endpoint = "http://api.acme.example/v1"
        expect(integration).not_to be_valid
        expect(integration.errors.messages[:resource_endpoint]).to eq(["url_is_invalid"])
      end

      it "refuses values that are not urls" do
        integration.resource_instructions = "not a url"
        expect(integration).not_to be_valid
        expect(integration.errors.messages[:resource_instructions]).to eq(["url_is_invalid"])
      end
    end
  end

  describe "#stripe_provider" do
    it "returns the stripe connection named by the code" do
      expect(integration.stripe_provider).to eq(organization.stripe_payment_providers.find_by(code: integration.payment_provider_code))
    end
  end

  describe "settings accessors" do
    it "assigns and retrieves the settings" do
      integration.scope = "acme_api:use"
      integration.resource_endpoint = "https://api.acme.example"
      integration.resource_instructions = "https://acme.example/agents"

      expect(integration.scope).to eq("acme_api:use")
      expect(integration.resource_endpoint).to eq("https://api.acme.example")
      expect(integration.resource_instructions).to eq("https://acme.example/agents")
    end
  end
end

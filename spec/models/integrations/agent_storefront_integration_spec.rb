# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::AgentStorefrontIntegration do
  subject(:integration) { build(:agent_storefront_integration, organization:) }

  let_it_be(:organization) { create_default(:organization) }

  describe "associations" do
    it do
      expect(integration).to have_many(:agent_registrations)
        .class_name("Agents::Registration")
        .with_foreign_key(:integration_id)
        .dependent(:delete_all)
    end
  end

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

  describe "plans validation" do
    let(:plan) { create(:plan, organization:) }

    it "accepts plans of the organization with optional top-up limits" do
      integration.plans = [{plan_code: plan.code, minimum_topup_cents: 500, maximum_topup_cents: 10_000}]
      expect(integration).to be_valid
    end

    it "refuses an unknown plan" do
      integration.plans = [{plan_code: "unknown"}]
      expect(integration).not_to be_valid
      expect(integration.errors.messages[:plans]).to eq(["plan_not_found"])
    end

    it "refuses a plan listed twice or limits that are not ordered positive integers" do
      [
        [{plan_code: plan.code}, {plan_code: plan.code}],
        [{plan_code: plan.code, minimum_topup_cents: 900, maximum_topup_cents: 100}],
        [{plan_code: plan.code, minimum_topup_cents: "500"}]
      ].each do |plans|
        integration.plans = plans
        expect(integration).not_to be_valid
        expect(integration.errors.messages[:plans]).to eq(["value_is_invalid"])
      end
    end

    it "refuses a plan that is being deleted" do
      plan.update!(pending_deletion: true)
      integration.plans = [{plan_code: plan.code}]

      expect(integration).not_to be_valid
      expect(integration.errors.messages[:plans]).to eq(["plan_not_found"])
    end

    it "turns input that is not a list of objects into a validation error" do
      integration.plans = {plan_code: plan.code}
      expect(integration.plans).to eq([{"plan_code" => plan.code}])

      integration.plans = ["not an object"]
      expect(integration).not_to be_valid
      expect(integration.errors.messages[:plans]).to eq(["plan_not_found"])
    end

    it "keeps only the known keys of each plan" do
      integration.plans = [{plan_code: plan.code, other: "x"}]
      expect(integration.plans).to eq([{"plan_code" => plan.code}])
    end
  end

  describe ".with_plan_code" do
    let(:plan) { create(:plan, organization:) }

    it "returns the storefronts that sell the plan" do
      integration.update!(plans: [{plan_code: plan.code}])

      expect(described_class.with_plan_code(plan.code)).to eq([integration])
      expect(described_class.with_plan_code("other")).to be_empty
    end
  end

  describe "#enrolled_agents?" do
    let(:registration) { create(:agent_registration, storefront: integration) }

    before { integration.save! }

    it "is true while a registration has an active subscription" do
      expect(integration.enrolled_agents?).to be(false)

      create(:subscription, organization:, external_id: Agents::ExternalIds.subscription(registration))
      expect(integration.enrolled_agents?).to be(true)
    end
  end

  describe "#stripe_provider" do
    it "returns the stripe connection named by the code" do
      expect(integration.stripe_provider).to eq(organization.stripe_payment_providers.find_by(code: integration.payment_provider_code))
    end
  end

  describe "#agent_url" do
    it "is built on the connection id" do
      integration.save!

      expect(integration.agent_url).to eq("#{ENV["LAGO_API_URL"]}/agents/v1/#{integration.id}")
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

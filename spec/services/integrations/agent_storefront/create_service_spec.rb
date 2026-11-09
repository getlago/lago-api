# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::AgentStorefront::CreateService do
  include_context "with mocked security logger"

  let(:organization) { create_default(:organization) }
  let(:membership) { create(:membership) }
  let(:stripe_provider) { create(:stripe_provider, organization:) }
  let(:redis_cache_url) { "redis://redis:6379" }
  let(:disable_wallet_refresh) { nil }

  before do
    stripe_provider
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("LAGO_REDIS_CACHE_URL").and_return(redis_cache_url)
    allow(ENV).to receive(:[]).with("LAGO_DISABLE_WALLET_REFRESH").and_return(disable_wallet_refresh)
  end

  describe "#call" do
    subject(:service_call) { described_class.call(params: create_args) }

    let(:name) { "Acme API" }
    let(:payment_provider_code) { stripe_provider.code }
    let(:resource_endpoint) { "https://api.acme.example/v1" }

    let(:create_args) do
      {
        name:,
        code: "acme_api",
        organization_id: organization.id,
        payment_provider_code:,
        resource_endpoint:,
        resource_instructions: "https://acme.example/agents"
      }
    end

    context "without premium license" do
      it "does not create an integration" do
        expect { service_call }.not_to change(Integrations::AgentStorefrontIntegration, :count)
      end

      it "returns an error" do
        result = service_call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
      end
    end

    context "with premium license", :premium do
      context "with agent storefront premium integration not present" do
        it "returns an error" do
          result = service_call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        end
      end

      context "with agent storefront premium integration present" do
        before { organization.update!(premium_integrations: %w[agent_storefront events_targeting_wallets]) }

        context "without validation errors" do
          it "creates an integration" do
            expect { service_call }.to change(Integrations::AgentStorefrontIntegration, :count).by(1)

            integration = Integrations::AgentStorefrontIntegration.order(:created_at).last
            expect(integration).to have_attributes(
              name:,
              code: "acme_api",
              payment_provider_code: stripe_provider.code,
              resource_endpoint:,
              resource_instructions: "https://acme.example/agents",
              scope: "acme_api:use"
            )
          end

          it_behaves_like "produces a security log", "integration.created" do
            before { service_call }
          end
        end

        context "without events targeting wallets" do
          before { organization.update!(premium_integrations: %w[agent_storefront]) }

          it "returns an error" do
            result = service_call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:base]).to eq(["events_targeting_wallets_disabled"])
          end
        end

        context "without a redis cache" do
          let(:redis_cache_url) { nil }

          it "returns an error" do
            result = service_call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:base]).to eq(["wallet_refresh_unavailable"])
          end
        end

        context "when the wallet refresh is disabled" do
          let(:disable_wallet_refresh) { "true" }

          it "returns an error" do
            result = service_call

            expect(result).not_to be_success
            expect(result.error.messages[:base]).to eq(["wallet_refresh_unavailable"])
          end
        end

        context "with an unknown stripe connection" do
          let(:payment_provider_code) { "unknown" }

          it "returns an error" do
            result = service_call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:payment_provider_code]).to eq(["payment_provider_not_found"])
          end
        end

        context "with an http endpoint" do
          let(:resource_endpoint) { "http://api.acme.example/v1" }

          it "returns an error" do
            result = service_call

            expect(result).not_to be_success
            expect(result.error.messages[:resource_endpoint]).to eq(["url_is_invalid"])
          end
        end

        context "with validation error" do
          let(:name) { nil }

          it "returns an error" do
            result = service_call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:name]).to eq(["value_is_mandatory"])
          end
        end

        context "with a database uniqueness conflict" do
          let(:integration) { build(:agent_storefront_integration, organization:) }
          let(:constraint) { "index_integrations_on_code_and_organization_id" }
          let(:database_result) { instance_double(PG::Result, error_field: constraint) }
          let(:database_error) { PG::UniqueViolation.new("duplicate value") }
          let(:write_error) { ActiveRecord::RecordNotUnique.new("duplicate value") }

          before do
            allow(database_error).to receive(:result).and_return(database_result)
            allow(integration).to receive(:save!) { raise write_error, cause: database_error }
            allow(Integrations::AgentStorefrontIntegration).to receive(:new).and_return(integration)
          end

          it "returns a validation error for a code collision" do
            expect(service_call.error.messages).to eq(code: ["value_already_exist"])
          end

          context "with another constraint" do
            let(:constraint) { "integrations_pkey" }

            it "does not hide the database error" do
              expect { service_call }.to raise_error(ActiveRecord::RecordNotUnique)
            end
          end
        end
      end
    end
  end
end

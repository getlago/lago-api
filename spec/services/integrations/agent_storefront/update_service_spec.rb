# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::AgentStorefront::UpdateService do
  include_context "with mocked security logger"

  let(:integration) { create(:agent_storefront_integration, organization:, code: "acme_api") }

  let_it_be(:organization, refind: true) { create_default(:organization) }
  let_it_be(:membership, refind: true) { create(:membership) }

  describe "#call" do
    subject(:service_call) { described_class.call(integration:, params: update_args) }

    before { integration }

    let(:name) { "Acme API updated" }
    let(:update_args) { {name:} }

    context "without premium license" do
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
          it "updates the integration" do
            result = service_call

            expect(result).to be_success
            expect(result.integration).to be_a(Integrations::AgentStorefrontIntegration)
            expect(result.integration.name).to eq(name)
          end

          it_behaves_like "produces a security log", "integration.updated" do
            before { service_call }
          end
        end

        context "when the code changes" do
          let(:update_args) { {code: "acme_api_v2", scope: "other:use"} }

          it "keeps the scope" do
            result = service_call

            expect(result).to be_success
            expect(result.integration.code).to eq("acme_api_v2")
            expect(result.integration.scope).to eq("acme_api:use")
          end
        end

        context "when the stripe connection changes" do
          let(:other_provider) { create(:stripe_provider, organization:) }
          let(:update_args) { {payment_provider_code: other_provider.code, resource_endpoint: nil} }

          it "updates the connection" do
            result = service_call

            expect(result).to be_success
            expect(result.integration.payment_provider_code).to eq(other_provider.code)
            expect(result.integration.resource_endpoint).to be_nil
          end
        end

        context "with an unknown stripe connection" do
          let(:update_args) { {payment_provider_code: "unknown"} }

          it "returns an error" do
            result = service_call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:payment_provider_code]).to eq(["payment_provider_not_found"])
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
      end
    end

    context "without integration" do
      let(:integration) { nil }

      it "returns an error" do
        result = service_call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.error_code).to eq("integration_not_found")
      end
    end
  end
end

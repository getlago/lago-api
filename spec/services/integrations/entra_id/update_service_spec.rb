# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::EntraId::UpdateService do
  include_context "with mocked security logger"

  let(:integration) { create(:entra_id_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }
  let(:domain) { "foo.bar" }
  let(:tenant_id) { SecureRandom.uuid }
  let(:host) { "login.microsoftonline.us" }

  describe "#call" do
    subject(:service_call) { described_class.call(integration:, params: update_args) }

    before { integration }

    let(:update_args) do
      {
        domain:,
        tenant_id:,
        host:
      }
    end

    context "without premium license" do
      it "returns an error" do
        result = service_call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
      end
    end

    context "with premium license", :premium do
      context "with entra_id premium integration not present" do
        it "returns an error" do
          result = service_call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        end
      end

      context "with entra_id premium integration present" do
        before { organization.update!(premium_integrations: ["entra_id"]) }

        context "without validation errors" do
          it "updates an integration" do
            service_call

            integration = Integrations::EntraIdIntegration.order(:updated_at).last

            expect(integration.domain).to eq(domain)
            expect(integration.tenant_id).to eq(tenant_id)
          end

          it_behaves_like "produces a security log", "integration.updated" do
            before { service_call }
          end
        end

        context "with validation error" do
          let(:domain) { nil }

          it "returns an error" do
            result = service_call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:domain]).to eq(["value_is_mandatory"])
          end
        end
      end
    end
  end
end

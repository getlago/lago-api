# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Okta::UpdateService do
  include_context "with mocked security logger"

  let(:integration) do
    create(:okta_integration, organization:, secrets: {client_secret: stored_client_secret}.to_json)
  end
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }
  let(:stored_client_secret) { "stored-client-secret" }
  let(:domain) { "foo.bar" }
  let(:organization_name) { "Footest" }
  let(:host) { "test.com" }

  describe "#call" do
    subject(:service_call) { described_class.call(integration:, params: update_args) }

    before { integration }

    let(:update_args) do
      {
        domain:,
        organization_name:,
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
      context "with okta premium integration not present" do
        it "returns an error" do
          result = service_call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        end
      end

      context "with okta premium integration present" do
        before { organization.update!(premium_integrations: ["okta"]) }

        context "without validation errors" do
          it "updates an integration" do
            service_call

            integration = Integrations::OktaIntegration.order(:updated_at).last

            expect(integration.domain).to eq(domain)
            expect(integration.organization_name).to eq(organization_name)
          end

          it_behaves_like "produces a security log", "integration.updated" do
            before { service_call }
          end

          context "without a client secret parameter" do
            it "keeps the stored client secret" do
              expect(service_call).to be_success
              expect(integration.reload.client_secret).to eq(stored_client_secret)
            end
          end

          context "with a blank client secret" do
            let(:update_args) { super().merge(client_secret: "") }

            it "keeps the stored client secret" do
              expect(service_call).to be_success
              expect(integration.reload.client_secret).to eq(stored_client_secret)
            end
          end

          context "with a masked client secret" do
            let(:update_args) { super().merge(client_secret: "••••••••…ret") }

            it "keeps the stored client secret" do
              expect(service_call).to be_success
              expect(integration.reload.client_secret).to eq(stored_client_secret)
            end
          end

          context "with a new client secret" do
            let(:new_client_secret) { "new-client-secret" }
            let(:update_args) { super().merge(client_secret: new_client_secret) }

            it "replaces the stored client secret" do
              expect(service_call).to be_success
              expect(integration.reload.client_secret).to eq(new_client_secret)
            end
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

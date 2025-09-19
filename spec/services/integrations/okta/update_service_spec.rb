# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Okta::UpdateService do
  let(:integration) { create(:okta_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }
  let(:domain) { "foo.bar" }
  let(:organization_name) { "Footest" }

  describe "#call" do
    subject(:service_call) { described_class.call(integration:, params: update_args) }

    before { integration }

    let(:update_args) do
      {
        domain:,
        organization_name:
      }
    end

    context "without premium license" do
      it "returns an error" do
        result = service_call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        end
      end
    end

    context "with premium license" do
      around { |test| lago_premium!(&test) }

      context "with okta premium integration not present" do
        it "returns an error" do
          result = service_call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          end
        end
      end

      context "with okta premium integration present" do
        before { organization.update!(premium_integrations: ["okta"]) }

        context "without validation errors" do
          it "updates an integration" do
            service_call

            integration = Integrations::OktaIntegration.order(:updated_at).last

            aggregate_failures do
              expect(integration.domain).to eq(domain)
              expect(integration.organization_name).to eq(organization_name)
            end
          end
        end

        context "with validation error" do
          let(:domain) { nil }

          it "returns an error" do
            result = service_call

            aggregate_failures do
              expect(result).not_to be_success
              expect(result.error).to be_a(BaseService::ValidationFailure)
              expect(result.error.messages[:domain]).to eq(["value_is_mandatory"])
            end
          end
        end
      end
    end
  end
end

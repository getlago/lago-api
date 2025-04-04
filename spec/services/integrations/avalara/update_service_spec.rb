# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Avalara::UpdateService, type: :service do
  let(:integration) { create(:avalara_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }

  describe "#call" do
    subject(:service_call) { described_class.call(integration:, params: update_args) }

    before { integration }

    let(:name) { "Avalara 1" }

    let(:update_args) do
      {
        name:,
        code: "anrok1",
        license_key: "123456789",
        account_id: "acc-id-1"
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

      context "without avalara premium integration" do
        it "returns an error" do
          result = service_call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          end
        end
      end

      context "with avalara premium integration" do
        before do
          organization.update!(premium_integrations: ["avalara"])
        end

        context "without validation errors" do
          it "updates an integration" do
            service_call

            integration = Integrations::AvalaraIntegration.order(:updated_at).last
            expect(integration.name).to eq(name)
            expect(integration.code).to eq("anrok1")
            expect(integration.account_id).to eq("acc-id-1")
            expect(integration.license_key).to eq("123456789")
          end

          it "returns an integration in result object" do
            result = service_call

            expect(result.integration).to be_a(Integrations::AvalaraIntegration)
          end
        end

        context "with validation error" do
          let(:name) { nil }

          it "returns an error" do
            result = service_call

            aggregate_failures do
              expect(result).not_to be_success
              expect(result.error).to be_a(BaseService::ValidationFailure)
              expect(result.error.messages[:name]).to eq(["value_is_mandatory"])
            end
          end
        end
      end
    end
  end
end

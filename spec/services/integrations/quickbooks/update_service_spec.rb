# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Quickbooks::UpdateService do
  include_context "with mocked security logger"

  let(:integration) { create(:quickbooks_integration, organization:) }

  let_it_be(:organization, refind: true) { create_default(:organization) }

  describe "#call" do
    subject(:service_call) { described_class.call(integration:, params: update_args) }

    before { integration }

    let(:update_args) do
      {
        name: "QuickBooks 1",
        code: "quickbooks1",
        sync_invoices: true,
        sync_credit_notes: true,
        sync_payments: true
      }
    end

    context "without integration" do
      let(:integration) { nil }

      it "returns a not found error" do
        result = service_call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("integration_not_found")
      end
    end

    context "with a Xero integration" do
      let(:integration) { create(:xero_integration, organization:, name: "Xero 1") }

      it "returns a not found error and leaves the Xero integration unchanged" do
        result = service_call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("integration_not_found")
        expect(integration.reload.name).to eq("Xero 1")
      end
    end

    context "without premium license" do
      it "returns an error" do
        result = service_call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("premium_integration_missing")
      end
    end

    context "with premium license", :premium do
      context "when quickbooks premium integration is not present" do
        it "returns an error and leaves the integration unchanged" do
          result = service_call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ForbiddenFailure)
          expect(result.error.code).to eq("premium_integration_missing")
          expect(integration.reload.name).to eq("QuickBooks Integration")
        end
      end

      context "when quickbooks premium integration is present" do
        before do
          organization.update!(premium_integrations: ["quickbooks"])
        end

        context "when a sync flag is set to null" do
          let(:integration) do
            create(
              :quickbooks_integration,
              organization:,
              settings: {realm_id: "1234567890", sandbox: false, sync_invoices: true, sync_credit_notes: true, sync_payments: true}
            )
          end
          let(:update_args) { {sync_invoices: nil} }

          it "stores false, as create does" do
            result = service_call

            expect(result).to be_success
            expect(integration.reload.settings["sync_invoices"]).to be(false)
            expect(integration.settings["sync_credit_notes"]).to be(true)
          end
        end

        context "without validation errors" do
          it "updates the name, the code and the sync flags" do
            result = service_call

            expect(result).to be_success
            expect(result.integration).to be_a(Integrations::QuickbooksIntegration)

            integration.reload
            expect(integration.name).to eq("QuickBooks 1")
            expect(integration.code).to eq("quickbooks1")
            expect(integration.sync_invoices).to be(true)
            expect(integration.sync_credit_notes).to be(true)
            expect(integration.sync_payments).to be(true)
          end

          it_behaves_like "produces a security log", "integration.updated" do
            before { service_call }
          end

          it_behaves_like "refused on a shadow organization", Integrations::QuickbooksIntegration
        end

        context "when only the name is given" do
          let(:integration) do
            create(
              :quickbooks_integration,
              organization:,
              settings: {realm_id: "1234567890", sandbox: false, sync_invoices: true, sync_credit_notes: true, sync_payments: true}
            )
          end

          let(:update_args) { {name: "QuickBooks 2"} }

          it "keeps the code and the sync flags" do
            service_call

            integration.reload
            expect(integration.name).to eq("QuickBooks 2")
            expect(integration.code).to eq("quickbooks")
            expect(integration.sync_invoices).to be(true)
            expect(integration.sync_credit_notes).to be(true)
            expect(integration.sync_payments).to be(true)
          end
        end

        context "when the sync flags are set to false" do
          let(:integration) do
            create(
              :quickbooks_integration,
              organization:,
              settings: {realm_id: "1234567890", sandbox: false, sync_invoices: true, sync_credit_notes: true, sync_payments: true}
            )
          end

          let(:update_args) { {sync_invoices: false, sync_credit_notes: true} }

          it "stores false and keeps the flag that was not passed" do
            service_call

            integration.reload
            expect(integration.sync_invoices).to be(false)
            expect(integration.sync_credit_notes).to be(true)
            expect(integration.sync_payments).to be(true)
          end
        end

        context "when only the code is given" do
          let(:update_args) { {code: "quickbooks2"} }

          it "keeps the name" do
            service_call

            integration.reload
            expect(integration.code).to eq("quickbooks2")
            expect(integration.name).to eq("QuickBooks Integration")
          end
        end

        context "when params carry connection_id, sandbox and realm_id" do
          let(:update_args) do
            {
              name: "QuickBooks 1",
              connection_id: "other-connection",
              sandbox: true,
              realm_id: "999"
            }
          end

          it "keeps connection_id, sandbox and realm_id unchanged" do
            result = service_call

            expect(result).to be_success

            integration.reload
            expect(integration.name).to eq("QuickBooks 1")
            expect(integration.connection_id).to eq("quickbooks-test-connection")
            expect(integration.sandbox?).to be(false)
            expect(integration.realm_id).to eq("1234567890")
          end
        end

        context "with a code already used in the organization" do
          let(:update_args) { {code: "taken-code"} }

          before { create(:xero_integration, organization:, code: "taken-code") }

          it "returns a validation error" do
            result = service_call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:code]).to eq(["value_already_exist"])
          end
        end

        context "with a blank name" do
          let(:update_args) { {name: nil} }

          it "returns a validation error" do
            result = service_call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:name]).to eq(["value_is_mandatory"])
          end
        end
      end
    end
  end
end

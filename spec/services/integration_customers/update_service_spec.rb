# frozen_string_literal: true

require "rails_helper"

RSpec.describe IntegrationCustomers::UpdateService do
  let(:integration) { create(:netsuite_integration, organization:) }

  let_it_be(:organization, refind: true) { create_default(:organization) }
  let_it_be(:membership, refind: true) { create(:membership) }
  let_it_be(:customer, refind: true) { create(:customer, organization:) }

  describe "#call" do
    subject(:service_call) { described_class.call(params:, integration:, integration_customer:) }

    let(:params) do
      {
        integration_type: "netsuite",
        integration_code:,
        sync_with_provider:,
        external_customer_id:,
        subsidiary_id:
      }
    end

    let(:subsidiary_id) { "1111" }
    let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }

    before { integration_customer }

    context "with netsuite premium integration present", :premium do
      let(:integration_code) { integration.code }
      let(:external_customer_id) { nil }
      let(:sync_with_provider) { true }
      let(:contact_id) { SecureRandom.uuid }
      let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }

      let(:update_result) do
        result = Integrations::Aggregator::Contacts::UpdateService::Result.new
        result.contact_id = contact_id
        result
      end

      before do
        organization.update!(premium_integrations: ["netsuite"])

        integration_customer

        allow(Integrations::Aggregator::Contacts::UpdateService)
          .to receive(:call).and_return(update_result)
      end

      context "when sync with provider is true" do
        let(:sync_with_provider) { true }

        context "when external customer id is present" do
          let(:external_customer_id) { SecureRandom.uuid }

          it "returns integration customer" do
            result = service_call

            expect(Integrations::Aggregator::Contacts::UpdateService).to have_received(:call)
            expect(result).to be_success
            expect(result.integration_customer).to eq(integration_customer)
            expect(result.integration_customer.external_customer_id).to eq(external_customer_id)
          end
        end

        context "when subsidiary id is present" do
          it "returns integration customer" do
            result = service_call

            expect(Integrations::Aggregator::Contacts::UpdateService).to have_received(:call)
            expect(result).to be_success
            expect(result.integration_customer).to eq(integration_customer)
          end
        end

        context "when customer external id is not present" do
          let(:external_customer_id) { nil }

          it "returns integration customer" do
            result = service_call

            expect(Integrations::Aggregator::Contacts::UpdateService).to have_received(:call)
            expect(result).to be_success
            expect(result.integration_customer).to eq(integration_customer)
          end
        end

        context "with anrok customer" do
          let(:external_customer_id) { SecureRandom.uuid }
          let(:integration_customer) { create(:anrok_customer, integration:, customer:) }

          it "does not calls aggregator update service" do
            service_call

            expect(Integrations::Aggregator::Contacts::UpdateService).not_to have_received(:call)
          end

          it "does not update integration customer" do
            service_call

            expect(integration_customer.reload.external_customer_id).not_to eq(external_customer_id)
          end
        end

        context "with salesforce customer" do
          let(:external_customer_id) { SecureRandom.uuid }
          let(:integration) { create(:salesforce_integration, organization:) }
          let(:integration_customer) { create(:salesforce_customer, integration:, customer:) }

          it "does not calls aggregator update service" do
            service_call

            expect(Integrations::Aggregator::Contacts::UpdateService).not_to have_received(:call)
          end

          it "does not update integration customer" do
            service_call

            expect(integration_customer.reload.external_customer_id).not_to eq(external_customer_id)
          end
        end
      end

      context "with quickbooks customer" do
        let(:external_customer_id) { "58" }
        let(:integration) { create(:quickbooks_integration, organization:) }
        let(:integration_customer) { create(:quickbooks_customer, integration:, customer:, code: "old_code") }
        let(:params) { {integration_type: "quickbooks", integration_code: integration.code, external_customer_id:, code: "qb_new"} }

        it "calls aggregator update service" do
          service_call

          expect(Integrations::Aggregator::Contacts::UpdateService)
            .to have_received(:call).with(integration:, integration_customer:)
        end

        it "stores the external customer id and the code" do
          result = service_call

          expect(result).to be_success
          expect(result.integration_customer).to eq(integration_customer)
          expect(integration_customer.reload).to have_attributes(external_customer_id: "58", code: "qb_new")
        end

        context "when the provider update fails" do
          let(:update_result) do
            Integrations::Aggregator::Contacts::UpdateService::Result.new
              .service_failure!(code: "realm_id_missing", message: "QuickBooks realm id is missing")
          end

          it "returns the provider failure and keeps the link edit" do
            result = service_call

            expect(result).not_to be_success
            expect(result.error.code).to eq("realm_id_missing")
            expect(integration_customer.reload).to have_attributes(external_customer_id: "58", code: "qb_new")
          end
        end

        context "when the link has no external customer id" do
          let(:external_customer_id) { nil }
          let(:integration_customer) do
            create(:quickbooks_customer, integration:, customer:, code: "old_code", external_customer_id: nil)
          end

          it "does not call aggregator update service" do
            result = service_call

            expect(Integrations::Aggregator::Contacts::UpdateService).not_to have_received(:call)
            expect(result).to be_success
            expect(integration_customer.reload).to have_attributes(external_customer_id: nil, code: "qb_new")
          end
        end
      end

      context "with xero customer" do
        let(:external_customer_id) { "58" }
        let(:integration) { create(:xero_integration, organization:) }
        let(:integration_customer) { create(:xero_customer, integration:, customer:) }
        let(:params) { {integration_type: "xero", integration_code: integration.code, external_customer_id:} }

        it "calls aggregator update service" do
          result = service_call

          expect(Integrations::Aggregator::Contacts::UpdateService)
            .to have_received(:call).with(integration:, integration_customer:)
          expect(result).to be_success
          expect(integration_customer.reload.external_customer_id).to eq("58")
        end
      end

      context "when sync with provider is false" do
        let(:sync_with_provider) { false }

        context "when customer external id is present" do
          let(:external_customer_id) { SecureRandom.uuid }

          it "calls aggregator update service" do
            service_call

            expect(Integrations::Aggregator::Contacts::UpdateService).to have_received(:call)
          end

          it "updates integration customer" do
            result = service_call

            expect(result.integration_customer.external_customer_id).to eq(external_customer_id)
          end
        end

        context "when customer external id is not present" do
          let(:external_customer_id) { nil }

          it "does not calls aggregator update service" do
            expect(Integrations::Aggregator::Contacts::UpdateService).not_to have_received(:call)
          end

          it "does not update integration customer" do
            result = service_call

            expect(result.integration_customer.external_customer_id).not_to eq(external_customer_id)
          end
        end
      end
    end
  end
end

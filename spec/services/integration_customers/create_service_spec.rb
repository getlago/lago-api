# frozen_string_literal: true

require "rails_helper"

RSpec.describe IntegrationCustomers::CreateService do
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:integration_type) { "netsuite" }

  let_it_be(:organization, refind: true) { create_default(:organization) }
  let_it_be(:membership, refind: true) { create(:membership) }
  let_it_be(:customer, refind: true) { create(:customer, organization:) }

  describe "#call" do
    subject(:service_call) { described_class.call(params:, integration:, customer:) }

    let(:params) do
      {
        integration_type:,
        integration_code:,
        sync_with_provider:,
        external_customer_id:,
        subsidiary_id:
      }
    end

    let(:subsidiary_id) { "1" }

    context "with quickbooks integration" do
      let(:integration) { create(:quickbooks_integration, organization:) }
      let(:integration_type) { "quickbooks" }
      let(:integration_code) { integration.code }
      let(:contact_id) { "1042" }
      let(:create_result) do
        result = Integrations::Aggregator::Contacts::CreateService::Result.new
        result.contact_id = contact_id
        result
      end

      before do
        allow(Integrations::Aggregator::Contacts::CreateService)
          .to receive(:call).and_return(create_result)
      end

      context "when customer external id is present" do
        let(:external_customer_id) { "58" }
        let(:sync_with_provider) { false }

        it "links the customer to the quickbooks customer" do
          expect { service_call }.to change(IntegrationCustomers::QuickbooksCustomer, :count).by(1)

          expect(service_call).to be_success
          expect(customer.reload.quickbooks_customer).to have_attributes(
            external_customer_id: "58",
            category: "accounting",
            is_default: true,
            code: integration.code,
            sync_with_provider: false
          )
          expect(Integrations::Aggregator::Contacts::CreateService).not_to have_received(:call)
        end

        context "when the customer already has a default accounting connection" do
          before do
            create(:xero_customer, customer:, organization:, category: :accounting, is_default: true)
          end

          it "does not mark the quickbooks connection as default" do
            result = service_call

            expect(result).to be_success
            expect(result.integration_customer).to be_a(IntegrationCustomers::QuickbooksCustomer)
            expect(result.integration_customer.is_default).to be(false)
          end
        end
      end

      context "when sync with provider is true and customer external id is not present" do
        let(:external_customer_id) { nil }
        let(:sync_with_provider) { true }

        it "creates the customer in QuickBooks and stores its id" do
          result = nil
          expect { result = service_call }.to change(IntegrationCustomers::QuickbooksCustomer, :count).by(1)

          expect(result).to be_success
          expect(result.integration_customer).to have_attributes(
            external_customer_id: contact_id,
            sync_with_provider: true,
            category: "accounting",
            is_default: true,
            code: integration.code
          )
          expect(Integrations::Aggregator::Contacts::CreateService)
            .to have_received(:call).with(integration:, customer:, subsidiary_id: nil)
        end

        context "when the customer creation in QuickBooks fails" do
          let(:create_result) do
            result = Integrations::Aggregator::Contacts::CreateService::Result.new
            result.service_failure!(code: "action_script_runtime_error", message: "Duplicate Name Exists Error")
            result
          end

          it "fails without creating integration customer" do
            result = nil
            expect { result = service_call }.not_to change(IntegrationCustomers::BaseCustomer, :count)

            expect(result).not_to be_success
            expect(result.error.code).to eq("action_script_runtime_error")
          end
        end
      end
    end

    context "with netsuite premium integration present", :premium do
      let(:integration_code) { integration.code }
      let(:external_customer_id) { nil }
      let(:sync_with_provider) { true }
      let(:contact_id) { SecureRandom.uuid }

      let(:create_result) do
        result = Integrations::Aggregator::Contacts::CreateService::Result.new
        result.contact_id = contact_id
        result
      end

      let(:integration_customer) { IntegrationCustomers::BaseCustomer.last }

      before do
        organization.update!(premium_integrations: ["netsuite"])

        allow(Integrations::Aggregator::Contacts::CreateService)
          .to receive(:call).and_return(create_result)
      end

      context "when sync with provider is true" do
        let(:sync_with_provider) { true }

        context "when customer external id is present" do
          let(:external_customer_id) { SecureRandom.uuid }

          it "returns integration customer" do
            result = service_call

            expect(Integrations::Aggregator::Contacts::CreateService).not_to have_received(:call)
            expect(result).to be_success
            expect(result.integration_customer).to eq(integration_customer)
            expect(result.integration_customer.external_customer_id).to eq(external_customer_id)
          end

          it "creates integration customer" do
            expect { service_call }.to change(IntegrationCustomers::BaseCustomer, :count).by(1)
          end

          context "when a code is provided" do
            let(:params) do
              {
                integration_type:,
                integration_code:,
                sync_with_provider:,
                external_customer_id:,
                subsidiary_id:,
                code: "ns_custom"
              }
            end

            it "persists the explicit code and defaults the first connection of the category" do
              result = service_call

              expect(result).to be_success
              expect(result.integration_customer.code).to eq("ns_custom")
              expect(result.integration_customer.is_default).to be(true)
            end
          end

          context "when the customer already has a default connection in the category" do
            before do
              create(:xero_customer, customer:, organization:, category: :accounting, is_default: true)
            end

            it "does not mark the new connection as default" do
              result = service_call

              expect(result).to be_success
              expect(result.integration_customer.is_default).to be(false)
            end
          end

          context "when the integration type is salesforce" do
            let(:integration) { create(:salesforce_integration, organization:) }
            let(:integration_type) { "salesforce" }

            it "returns integration customer with sync_with_provider true" do
              result = service_call

              expect(Integrations::Aggregator::Contacts::CreateService).not_to have_received(:call)
              expect(result).to be_success
              expect(result.integration_customer).to eq(integration_customer)
              expect(result.integration_customer.external_customer_id).to eq(external_customer_id)
              expect(result.integration_customer.sync_with_provider).to eq(true)
            end
          end
        end

        context "when customer external id is not present" do
          let(:external_customer_id) { nil }

          it "returns integration customer" do
            result = service_call

            expect(Integrations::Aggregator::Contacts::CreateService).to have_received(:call)
            expect(result).to be_success
            expect(result.integration_customer).to eq(integration_customer)
          end

          it "creates integration customer" do
            expect { service_call }.to change(IntegrationCustomers::NetsuiteCustomer, :count).by(1)
          end

          context "with anrok integration" do
            let(:integration) { create(:anrok_integration, organization:) }
            let(:params) do
              {
                integration_type: "anrok",
                integration_code:,
                sync_with_provider:,
                external_customer_id:
              }
            end

            it "creates integration customer" do
              expect { service_call }.to change(IntegrationCustomers::AnrokCustomer, :count).by(1)
            end
          end
        end
      end

      context "when sync with provider is false" do
        let(:sync_with_provider) { false }

        context "when customer external id is present" do
          let(:external_customer_id) { SecureRandom.uuid }

          it "does not calls aggregator create service" do
            service_call

            expect(Integrations::Aggregator::Contacts::CreateService).not_to have_received(:call)
          end

          it "creates integration customer" do
            expect { service_call }.to change(IntegrationCustomers::BaseCustomer, :count).by(1)
          end
        end

        context "when customer external id is not present" do
          let(:external_customer_id) { nil }

          it "does not calls aggregator create service" do
            service_call

            expect(Integrations::Aggregator::Contacts::CreateService).not_to have_received(:call)
          end

          it "does not create integration customer" do
            expect { service_call }.not_to change(IntegrationCustomers::BaseCustomer, :count)
          end
        end
      end
    end
  end
end

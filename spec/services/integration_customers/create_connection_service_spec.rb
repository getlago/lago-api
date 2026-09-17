# frozen_string_literal: true

require "rails_helper"

RSpec.describe IntegrationCustomers::CreateConnectionService do
  subject(:create_service) { described_class.new(customer:, params:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:integration) { create(:netsuite_integration, organization:, code: "ns_main") }
  let(:external_customer_id) { SecureRandom.uuid }

  let(:params) do
    {
      integration_id: integration.id,
      code: "netsuite_main",
      external_customer_id:,
      subsidiary_id: "1"
    }
  end

  describe "#call" do
    subject(:result) { create_service.call }

    context "when customer is not found" do
      let(:customer) { nil }

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("customer_not_found")
      end
    end

    context "when the integration does not exist" do
      let(:params) { {integration_id: SecureRandom.uuid, external_customer_id:} }

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("integration_not_found")
      end
    end

    context "when the integration belongs to another organization" do
      let(:integration) { create(:netsuite_integration, code: "ns_main") }

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("integration_not_found")
      end
    end

    context "when the integration has no connection category" do
      let(:integration) { create(:okta_integration, organization:) }
      let(:params) { {integration_id: integration.id, external_customer_id:} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:integration_id]).to eq(["value_is_invalid"])
      end
    end

    context "when the organization has several integrations of the same type" do
      let(:other_integration) { create(:netsuite_integration, organization:, code: "ns_sub") }

      before { other_integration }

      it "attaches the connection to the requested integration" do
        expect(result).to be_success
        expect(result.integration_customer.integration).to eq(integration)
      end
    end

    context "when the customer is a partner account" do
      let(:customer) { create(:customer, organization:, account_type: "partner") }

      it "returns a successful result without an integration customer" do
        expect(result).to be_success
        expect(result.integration_customer).to be_nil
      end

      it "does not create the integration customer" do
        expect { create_service.call }.not_to change(IntegrationCustomers::BaseCustomer, :count)
      end
    end

    context "when neither external_customer_id nor sync_with_provider is given" do
      let(:params) { {integration_id: integration.id, code: "netsuite_main"} }

      it "returns a successful result without an integration customer" do
        expect(result).to be_success
        expect(result.integration_customer).to be_nil
      end

      it "does not create the integration customer" do
        expect { create_service.call }.not_to change(IntegrationCustomers::BaseCustomer, :count)
      end
    end

    context "with a valid integration" do
      it "creates the integration customer" do
        expect { create_service.call }.to change(IntegrationCustomers::NetsuiteCustomer, :count).by(1)
      end

      it "returns the integration customer with its attributes" do
        integration_customer = result.integration_customer

        expect(result).to be_success
        expect(integration_customer).to be_a(IntegrationCustomers::NetsuiteCustomer)
        expect(integration_customer.code).to eq("netsuite_main")
        expect(integration_customer.category).to eq("accounting")
        expect(integration_customer.integration).to eq(integration)
        expect(integration_customer.external_customer_id).to eq(external_customer_id)
        expect(integration_customer.subsidiary_id).to eq("1")
      end

      it "marks the first connection of the category as the default one" do
        expect(result.integration_customer).to be_is_default
      end
    end

    context "when no code is given" do
      let(:params) { {integration_id: integration.id, external_customer_id:} }

      it "derives the code from the integration" do
        expect(result).to be_success
        expect(result.integration_customer.code).to eq("ns_main")
      end
    end

    context "when the category is a tax one" do
      let(:integration) { create(:anrok_integration, organization:, code: "anrok_main") }
      let(:params) { {integration_id: integration.id, external_customer_id:} }

      it "derives the category from the integration type" do
        expect(result).to be_success
        expect(result.integration_customer.category).to eq("tax")
      end
    end

    context "when the customer already has a connection in another category" do
      let(:crm_connection) { create(:salesforce_customer, organization:, customer:, category: "crm", is_default: true) }

      before { crm_connection }

      it "marks the new connection as the default one of its category" do
        expect(result.integration_customer).to be_is_default
      end

      it "leaves the connection of the other category untouched" do
        expect { create_service.call }.not_to change { crm_connection.reload.is_default }
      end
    end

    context "when the customer already has a default connection in the same category" do
      let(:accounting_connection) do
        create(:xero_customer, organization:, customer:, category: "accounting", code: "xero_main", is_default: true)
      end

      before { accounting_connection }

      it "does not mark the new connection as the default one" do
        expect(result.integration_customer).not_to be_is_default
      end

      it "leaves the existing default untouched" do
        expect { create_service.call }.not_to change { accounting_connection.reload.is_default }
      end
    end

    context "when the code is already used in the category" do
      before do
        create(:xero_customer, organization:, customer:, category: "accounting", code: "netsuite_main")
      end

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
      end

      it "does not leave a connection behind" do
        expect { create_service.call }.not_to change(IntegrationCustomers::NetsuiteCustomer, :count)
      end
    end

    context "when syncing with the provider" do
      let(:params) do
        {
          integration_id: integration.id,
          code: "netsuite_main",
          sync_with_provider: true,
          subsidiary_id: "1"
        }
      end

      let(:contact_id) { SecureRandom.uuid }

      let(:aggregator_result) do
        aggregator_result = Integrations::Aggregator::Contacts::CreateService::Result.new
        aggregator_result.contact_id = contact_id
        aggregator_result
      end

      before do
        allow(Integrations::Aggregator::Contacts::CreateService).to receive(:call).and_return(aggregator_result)
      end

      it "creates the integration customer from the provider contact" do
        integration_customer = result.integration_customer

        expect(result).to be_success
        expect(integration_customer.external_customer_id).to eq(contact_id)
        expect(integration_customer.code).to eq("netsuite_main")
        expect(integration_customer.category).to eq("accounting")
        expect(integration_customer).to be_is_default
      end
    end

    context "when the provider sync fails" do
      let(:params) { {integration_id: integration.id, sync_with_provider: true, subsidiary_id: "1"} }

      let(:aggregator_result) do
        Integrations::Aggregator::Contacts::CreateService::Result.new
          .service_failure!(code: "action_script_runtime_error", message: "Contact creation failed")
      end

      before do
        allow(Integrations::Aggregator::Contacts::CreateService).to receive(:call).and_return(aggregator_result)
      end

      it "returns the provider error" do
        expect(result).not_to be_success
        expect(result.error.code).to eq("action_script_runtime_error")
      end
    end
  end
end

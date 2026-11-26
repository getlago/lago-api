# frozen_string_literal: true

require "rails_helper"

RSpec.describe IntegrationCustomers::QuickbooksService do
  let(:integration) { create(:quickbooks_integration, organization:) }

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership) { create(:membership) }
  let_it_be(:customer) { create(:customer, organization:) }

  describe "#create" do
    subject(:service_call) do
      IntegrationCustomers::Factory.new_instance(integration:, customer:, subsidiary_id: nil, sync_with_provider: true).create
    end

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

    it "is the service the factory builds for a QuickBooks integration" do
      expect(IntegrationCustomers::Factory.new_instance(integration:, customer:, subsidiary_id: nil)).to be_a(described_class)
    end

    it "creates the contact in QuickBooks" do
      service_call

      expect(Integrations::Aggregator::Contacts::CreateService)
        .to have_received(:call).with(integration:, customer:, subsidiary_id: nil)
    end

    it "returns the integration customer storing the QuickBooks id" do
      result = service_call

      expect(result).to be_success
      expect(result.integration_customer).to be_a(IntegrationCustomers::QuickbooksCustomer)
      expect(result.integration_customer).to have_attributes(
        type: "IntegrationCustomers::QuickbooksCustomer",
        external_customer_id: contact_id,
        integration_id: integration.id,
        customer_id: customer.id,
        organization_id: organization.id,
        sync_with_provider: true
      )
    end

    it "creates integration customer" do
      expect { service_call }.to change(IntegrationCustomers::QuickbooksCustomer, :count).by(1)
    end

    context "when the contact creation fails" do
      let(:create_result) do
        result = Integrations::Aggregator::Contacts::CreateService::Result.new
        result.service_failure!(code: "action_script_runtime_error", message: "Duplicate Name Exists Error")
        result
      end

      it "returns the contact creation failure" do
        result = service_call

        expect(result).not_to be_success
        expect(result).to eq(create_result)
        expect(result.error.code).to eq("action_script_runtime_error")
      end

      it "does not create integration customer" do
        expect { service_call }.not_to change(IntegrationCustomers::BaseCustomer, :count)
      end
    end
  end
end

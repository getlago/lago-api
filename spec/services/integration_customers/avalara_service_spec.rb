# frozen_string_literal: true

require "rails_helper"

RSpec.describe IntegrationCustomers::AvalaraService, type: :service do
  let(:integration) { create(:avalara_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }
  let(:customer) { create(:customer, organization:) }

  describe "#create" do
    subject(:service_call) { described_class.new(integration:, customer:, subsidiary_id: nil).create }

    let(:create_result) do
      BaseService::Result.new
    end
    let(:aggregator_contacts_create_service) do
      instance_double(Integrations::Aggregator::Contacts::CreateService)
    end

    before do
      allow(Integrations::Aggregator::Contacts::CreateService)
        .to receive(:new).and_return(aggregator_contacts_create_service)

      allow(aggregator_contacts_create_service).to receive(:call).and_return(create_result)
    end

    it "returns integration customer" do
      result = service_call

      aggregate_failures do
        expect(aggregator_contacts_create_service).to have_received(:call)
        expect(result).to be_success
        expect(result.integration_customer.external_customer_id).to eq(customer.id)
        expect(result.integration_customer.integration_id).to eq(integration.id)
        expect(result.integration_customer.customer_id).to eq(customer.id)
        expect(result.integration_customer.type).to eq("IntegrationCustomers::AvalaraCustomer")
      end
    end

    it "creates integration customer" do
      expect { service_call }.to change(IntegrationCustomers::AvalaraCustomer, :count).by(1)
    end
  end
end

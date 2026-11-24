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

    before do
      integration
      allow(Integrations::Aggregator::Contacts::CreateService).to receive(:call)
    end

    it "is the service the factory builds for a QuickBooks integration" do
      expect(IntegrationCustomers::Factory.new_instance(integration:, customer:, subsidiary_id: nil)).to be_a(described_class)
    end

    it "returns a success without integration customer" do
      result = service_call

      expect(result).to be_success
      expect(result.integration_customer).to be_nil
    end

    it "does not create the contact in the provider" do
      service_call

      expect(Integrations::Aggregator::Contacts::CreateService).not_to have_received(:call)
    end

    it "does not create integration customer" do
      expect { service_call }.not_to change(IntegrationCustomers::BaseCustomer, :count)
    end
  end
end

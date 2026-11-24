# frozen_string_literal: true

require "rails_helper"

RSpec.describe IntegrationCustomers::UpdateJob do
  subject(:create_job) { described_class }

  let(:integration) { create(:netsuite_integration) }
  let(:integration_customer) { create(:netsuite_customer, integration:) }
  let(:result) { IntegrationCustomers::UpdateService::Result.new }
  let(:integration_customer_params) do
    {
      sync_with_provider: true
    }
  end

  before do
    allow(IntegrationCustomers::UpdateService).to receive(:call).and_return(result)
  end

  it "calls the update service" do
    described_class.perform_now(integration_customer_params:, integration:, integration_customer:)

    expect(IntegrationCustomers::UpdateService).to have_received(:call)
  end

  context "with a quickbooks integration customer" do
    let(:integration) { create(:quickbooks_integration) }
    let(:integration_customer) { create(:quickbooks_customer, integration:) }
    let(:integration_customer_params) do
      {integration_type: "quickbooks", integration_code: integration.code, external_customer_id: "58"}
    end

    before do
      allow(IntegrationCustomers::UpdateService).to receive(:call).and_call_original
      allow(Integrations::Aggregator::Contacts::UpdateService).to receive(:call)
    end

    it "stores the new external customer id without calling the provider" do
      described_class.perform_now(integration_customer_params:, integration:, integration_customer:)

      expect(integration_customer.reload.external_customer_id).to eq("58")
      expect(Integrations::Aggregator::Contacts::UpdateService).not_to have_received(:call)
    end
  end
end

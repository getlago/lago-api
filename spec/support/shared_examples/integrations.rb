# frozen_string_literal: true

RSpec.shared_examples 'syncs invoice' do
  context 'when it should sync invoice' do
    let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }
    let(:integration) { create(:netsuite_integration, organization:, sync_invoices: true) }

    before do
      allow(Integrations::Aggregator::Invoices::CreateJob).to receive(:perform_later)
      integration_customer
      service_call
    end

    it 'enqueues Integrations::Aggregator::Invoices::CreateJob' do
      expect(Integrations::Aggregator::Invoices::CreateJob).to have_received(:perform_later)
    end
  end
end

RSpec.shared_examples 'syncs sales order' do
  context 'when it should sync sales order' do
    let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }
    let(:integration) { create(:netsuite_integration, organization:, sync_sales_orders: true) }

    before do
      allow(Integrations::Aggregator::SalesOrders::CreateJob).to receive(:perform_later)
      integration_customer
      service_call
    end

    it 'enqueues Integrations::Aggregator::SalesOrders::CreateJob' do
      expect(Integrations::Aggregator::SalesOrders::CreateJob).to have_received(:perform_later)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::FetchItemsJob do
  subject(:fetch_items_job) { described_class }

  let(:integration) { create(:netsuite_integration) }
  let(:result) { Integrations::Aggregator::ItemsService::Result.new }

  it "calls the items service" do
    allow(Integrations::Aggregator::ItemsService).to receive(:call).and_return(result)

    described_class.perform_now(integration:)

    expect(Integrations::Aggregator::ItemsService).to have_received(:call)
  end

  context "when the QuickBooks integration is flagged with a realm id mismatch" do
    let(:integration) do
      create(:quickbooks_integration, settings: {realm_id: "1234567890", sandbox: false, realm_id_mismatch: true})
    end
    let(:integration_item) { create(:integration_item, integration:) }

    before { integration_item }

    it "fails on the first execution without any request to Nango or retry" do
      expect { described_class.perform_now(integration:) }
        .to raise_error(BaseService::ForbiddenFailure) { |error| expect(error.code).to eq("realm_id_changed") }

      expect(a_request(:any, /api.nango.dev/)).not_to have_been_made
      expect(described_class).not_to have_been_enqueued
      expect(integration.integration_items.reload).to eq([integration_item])
    end
  end
end

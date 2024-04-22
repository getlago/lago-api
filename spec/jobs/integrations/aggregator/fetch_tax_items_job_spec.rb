# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::FetchTaxItemsJob, type: :job do
  subject(:fetch_tax_items_job) { described_class }

  let(:tax_items_service) { instance_double(Integrations::Aggregator::TaxItemsService) }
  let(:integration) { create(:netsuite_integration) }
  let(:result) { BaseService::Result.new }

  before do
    allow(Integrations::Aggregator::TaxItemsService).to receive(:new).and_return(tax_items_service)
    allow(tax_items_service).to receive(:call).and_return(result)
  end

  it 'calls the tax items service' do
    described_class.perform_now(integration:)

    expect(Integrations::Aggregator::TaxItemsService).to have_received(:new)
    expect(tax_items_service).to have_received(:call)
  end
end

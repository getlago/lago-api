# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::FetchItemsJob, type: :job do
  subject(:fetch_items_job) { described_class }

  let(:items_service) { instance_double(Integrations::Aggregator::ItemsService) }
  let(:integration) { create(:netsuite_integration) }
  let(:result) { BaseService::Result.new }

  before do
    allow(Integrations::Aggregator::ItemsService).to receive(:new).and_return(items_service)
    allow(items_service).to receive(:call).and_return(result)
  end

  it 'calls the items service' do
    described_class.perform_now(integration:)

    expect(Integrations::Aggregator::ItemsService).to have_received(:new)
    expect(items_service).to have_received(:call)
  end
end

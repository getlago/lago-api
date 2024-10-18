# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::Invoices::Crm::UpdateJob, type: :job do
  subject(:create_job) { described_class }

  let(:service) { instance_double(Integrations::Aggregator::Invoices::Crm::UpdateService) }
  let(:invoice) { create(:invoice) }
  let(:result) { BaseService::Result.new }

  before do
    allow(Integrations::Aggregator::Invoices::Crm::UpdateService).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_return(result)
  end

  it 'calls the aggregator create invoice crm service' do
    described_class.perform_now(invoice:)

    aggregate_failures do
      expect(Integrations::Aggregator::Invoices::Crm::UpdateService).to have_received(:new)
      expect(service).to have_received(:call)
    end
  end
end

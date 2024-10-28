# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::Subscriptions::Crm::CreateJob, type: :job do
  subject(:create_job) { described_class }

  let(:service) { instance_double(Integrations::Aggregator::Subscriptions::Crm::CreateService) }
  let(:subscription) { create(:subscription) }
  let(:result) { BaseService::Result.new }

  before do
    allow(Integrations::Aggregator::Subscriptions::Crm::CreateService).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_return(result)
  end

  context 'when the service call is not successful' do
    before do
      allow(result).to receive(:success?).and_return(false)
      allow(result).to receive(:raise_if_error!).and_raise(StandardError)
    end

    it 'raises an error' do
      expect { create_job.perform_now(subscription:) }.to raise_error(StandardError)
    end
  end

  context 'when the service call is successful' do
    it 'calls the aggregator create subscription crm service' do
      described_class.perform_now(subscription:)

      aggregate_failures do
        expect(Integrations::Aggregator::Subscriptions::Crm::CreateService).to have_received(:new)
        expect(service).to have_received(:call)
      end
    end

    it 'enqueues the aggregator create customer association subscription job' do
      expect do
        described_class.perform_now(subscription:)
      end.to have_enqueued_job(Integrations::Aggregator::Subscriptions::Crm::CreateCustomerAssociationJob).with(subscription:)
    end
  end
end

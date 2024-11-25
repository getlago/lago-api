# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob, type: :job do
  subject(:create_job) { described_class }

  let(:service) { instance_double(Integrations::Aggregator::Subscriptions::Hubspot::UpdateService) }
  let(:subscription) { create(:subscription) }
  let(:result) { BaseService::Result.new }

  before do
    allow(Integrations::Aggregator::Subscriptions::Hubspot::UpdateService).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_return(result)
  end

  it 'calls the aggregator create subscription hubspot service' do
    described_class.perform_now(subscription:)

    aggregate_failures do
      expect(Integrations::Aggregator::Subscriptions::Hubspot::UpdateService).to have_received(:new)
      expect(service).to have_received(:call)
    end
  end
end

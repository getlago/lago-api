# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::Payments::CreateJob, type: :job do
  subject(:create_job) { described_class }

  let(:service) { instance_double(Integrations::Aggregator::Payments::CreateService) }
  let(:payment) { create(:payment) }
  let(:result) { BaseService::Result.new }

  before do
    allow(Integrations::Aggregator::Payments::CreateService).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_return(result)
  end

  it 'calls the aggregator create payment service' do
    described_class.perform_now(payment:)

    aggregate_failures do
      expect(Integrations::Aggregator::Payments::CreateService).to have_received(:new)
      expect(service).to have_received(:call)
    end
  end
end

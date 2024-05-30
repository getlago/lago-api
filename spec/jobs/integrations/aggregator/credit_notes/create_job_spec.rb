# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::CreditNotes::CreateJob, type: :job do
  subject(:create_job) { described_class }

  let(:service) { instance_double(Integrations::Aggregator::CreditNotes::CreateService) }
  let(:credit_note) { create(:credit_note) }
  let(:result) { BaseService::Result.new }

  before do
    allow(Integrations::Aggregator::CreditNotes::CreateService).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_return(result)
  end

  it 'calls the aggregator create credit_note service' do
    described_class.perform_now(credit_note:)

    aggregate_failures do
      expect(Integrations::Aggregator::CreditNotes::CreateService).to have_received(:new)
      expect(service).to have_received(:call)
    end
  end
end

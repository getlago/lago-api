# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::GeneratePdfJob, type: :job do
  let(:invoice) { create(:invoice) }

  let(:result) { BaseService::Result.new }

  let(:generate_service) do
    instance_double(Invoices::GeneratePdfService)
  end

  it 'delegates to the Generate service' do
    allow(Invoices::GeneratePdfService).to receive(:new)
      .with(invoice:, context: 'api')
      .and_return(generate_service)
    allow(generate_service).to receive(:call)
      .and_return(result)

    described_class.perform_now(invoice)

    expect(Invoices::GeneratePdfService).to have_received(:new)
    expect(generate_service).to have_received(:call)
  end
end

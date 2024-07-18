# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::FinalizeJob, type: :job do
  let(:invoice) { create(:invoice) }

  let(:result) { BaseService::Result.new }

  let(:finalize_service) do
    instance_double(Invoices::RefreshDraftAndFinalizeService)
  end

  it 'delegates to the Generate service' do
    allow(Invoices::RefreshDraftAndFinalizeService).to receive(:new)
      .with(invoice:)
      .and_return(finalize_service)
    allow(finalize_service).to receive(:call)
      .and_return(result)

    described_class.perform_now(invoice)

    expect(Invoices::RefreshDraftAndFinalizeService).to have_received(:new)
    expect(finalize_service).to have_received(:call)
  end
end

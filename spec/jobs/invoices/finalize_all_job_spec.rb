# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::FinalizeAllJob, type: :job do
  subject(:finalize_all_job) { described_class }

  let(:finalize_batch_service) { instance_double(Invoices::FinalizeBatchService) }
  let(:result) { BaseService::Result.new }
  let(:organization) { create(:organization) }
  let(:invoice) { create(:invoice, organization:) }

  before do
    allow(Invoices::FinalizeBatchService).to receive(:new).and_return(finalize_batch_service)
    allow(finalize_batch_service).to receive(:call)g.and_return(result)
  end

  it 'calls the retry batch service' do
    finalize_all_job.perform_now(organization:, invoice_ids: [invoice.id])

    expect(Invoices::FinalizeBatchService).to have_received(:new)
    expect(finalize_batch_service).to have_received(:call)
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::RefreshBatchJob, type: :job do
  subject(:refresh_batch_job) { described_class }

  let(:refresh_service) { instance_double(Invoices::RefreshDraftService) }
  let(:result) { BaseService::Result.new }

  let(:invoice) do
    create(:invoice, status: :draft)
  end

  before do
    invoice
    allow(Invoices::RefreshDraftService).to receive(:new)
      .with(invoice:)
      .and_return(refresh_service)
    allow(refresh_service).to receive(:disable_draft_invoices_refresh!).and_return(nil)
    allow(refresh_service).to receive(:enable_draft_invoices_refresh!).and_return(nil)
    allow(refresh_service).to receive(:call).and_return(result)
  end

  it 'refreshes draft invoices' do
    allow(refresh_service).to receive(:draft_invoices_refresh_enabled?).and_return(true)

    refresh_batch_job.perform_now([invoice.id])

    expect(Invoices::RefreshDraftService).to have_received(:new).twice
    expect(refresh_service).to have_received(:call)
  end

  context 'when batch refresh draft invoices action is not enabled' do
    it 'does not refresh draft invoices' do
      allow(refresh_service).to receive(:draft_invoices_refresh_enabled?).and_return(false)

      refresh_batch_job.perform_now([invoice.id])

      expect(Invoices::RefreshDraftService).to have_received(:new).once
      expect(refresh_service).not_to have_received(:call)
    end
  end
end

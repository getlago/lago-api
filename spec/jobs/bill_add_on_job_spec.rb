# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillAddOnJob, type: :job do
  let(:applied_add_on) { create(:applied_add_on) }
  let(:date) { Time.zone.now.to_date }

  let(:invoice_service) { instance_double(Invoices::AddOnService) }
  let(:result) { BaseService::Result.new }

  before do
    allow(Invoices::AddOnService).to receive(:new)
      .with(applied_add_on: applied_add_on, date: date)
      .and_return(invoice_service)
    allow(invoice_service).to receive(:create)
      .and_return(result)
  end

  it 'calls the add on create service' do
    described_class.perform_now(applied_add_on, date)

    expect(Invoices::AddOnService).to have_received(:new)
    expect(invoice_service).to have_received(:create)
  end

  context 'when result is a failure' do
    let(:result) do
      BaseService::Result.new.fail!(code: 'error')
    end

    it 'raises an error' do
      expect do
        described_class.perform_now(applied_add_on, date)
      end.to raise_error(BaseService::FailedResult)

      expect(Invoices::AddOnService).to have_received(:new)
      expect(invoice_service).to have_received(:create)
    end
  end
end

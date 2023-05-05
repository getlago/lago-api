# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TaxRates::DestroyService, type: :service do
  subject(:destroy_service) { described_class.new(tax_rate:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:tax_rate) { create(:tax_rate, organization:) }

  describe '#call' do
    before { tax_rate }

    it 'destroys the tax rate' do
      aggregate_failures do
        expect { destroy_service.call }.to change(TaxRate, :count).by(-1)
      end
    end

    it 'refreshes draft invoices' do
      draft_invoice = create(:invoice, :draft, organization:)

      expect do
        destroy_service.call
      end.to have_enqueued_job(Invoices::RefreshBatchJob).with([draft_invoice.id])
    end

    context 'when tax rate is not found' do
      let(:tax_rate) { nil }

      it 'returns an error' do
        result = destroy_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('tax_rate_not_found')
        end
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Customers::AppliedTaxes::DestroyService, type: :service do
  subject(:destroy_service) { described_class.new(applied_tax:) }

  let(:applied_tax) { create(:customer_applied_tax) }
  let(:customer) { applied_tax.customer }

  describe '#call' do
    before { applied_tax }

    it 'destroys the applied tax' do
      expect { destroy_service.call }.to change(Customer::AppliedTax, :count).by(-1)
    end

    it 'refreshes draft invoices' do
      draft_invoice = create(:invoice, :draft, organization: customer.organization, customer:)

      expect do
        destroy_service.call
      end.to have_enqueued_job(Invoices::RefreshBatchJob).with([draft_invoice.id])
    end

    context 'when applied tax is not found' do
      let(:applied_tax) { nil }

      it 'returns an error' do
        result = destroy_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('applied_tax_not_found')
        end
      end
    end
  end
end

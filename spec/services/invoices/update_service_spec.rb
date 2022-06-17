# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::UpdateService do
  subject(:invoice_service) { described_class.new }

  let(:invoice) { create(:invoice) }
  let(:invoice_id) { invoice.id }

  describe 'update_from_api' do
    let(:update_args) do
      {
        status: 'succeeded',
      }
    end

    it 'updates the invoice' do
      result = invoice_service.update_from_api(
        invoice_id: invoice_id,
        params: update_args,
      )

      aggregate_failures do
        expect(result).to be_success
        expect(result.invoice).to eq(invoice)
        expect(result.invoice.status).to eq(update_args[:status])
      end
    end

    context 'when invoice does not exist' do
      let(:invoice_id) { 'invalid' }

      it 'returns an error' do
        result = invoice_service.update_from_api(
          invoice_id: invoice_id,
          params: update_args,
        )

        expect(result).not_to be_success
        expect(result.error).to eq('not_found')
      end
    end

    context 'when invoice status is invalid' do
      let(:update_args) do
        {
          status: 'Foo Bar',
        }
      end

      it 'returns an error' do
        result = invoice_service.update_from_api(
          invoice_id: invoice_id,
          params: update_args,
        )

        expect(result).not_to be_success
        expect(result.error).to eq('invalid_status')
      end
    end

    context 'when invoice status is not present' do
      let(:update_args) {{}}

      it 'returns an error' do
        result = invoice_service.update_from_api(
          invoice_id: invoice_id,
          params: update_args,
        )

        expect(result).not_to be_success
        expect(result.error).to eq('invalid_status')
      end
    end

    context 'with validation error' do
      before do
        invoice.issuing_date = nil
        invoice.save(validate: false)
      end

      it 'returns an error' do
        result = invoice_service.update_from_api(
          invoice_id: invoice_id,
          params: update_args,
        )

        expect(result).not_to be_success
        expect(result.error_code).to eq('unprocessable_entity')
      end
    end
  end
end

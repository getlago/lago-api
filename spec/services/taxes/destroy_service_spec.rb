# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Taxes::DestroyService, type: :service do
  subject(:destroy_service) { described_class.new(tax:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:tax) { create(:tax, organization:) }

  let(:customer) { create(:customer, organization:) }

  describe '#call' do
    before { tax }

    it 'destroys the tax' do
      aggregate_failures do
        expect { destroy_service.call }.to change(Tax, :count).by(-1)
      end
    end

    it 'marks invoices as ready to be refreshed' do
      draft_invoice = create(:invoice, :draft, organization:, customer:)

      expect { destroy_service.call }.to change { draft_invoice.reload.ready_to_be_refreshed }.to(true)
    end

    context 'when tax is not found' do
      let(:tax) { nil }

      it 'returns an error' do
        result = destroy_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('tax_not_found')
        end
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdjustedFees::DestroyService, type: :service do
  subject(:destroy_service) { described_class.new(fee:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:invoice) { create(:invoice, status: :draft, organization:) }
  let(:fee) { create(:charge_fee, invoice:) }
  let(:adjusted_fee) { create(:adjusted_fee, invoice:, fee:) }

  describe '#call' do
    before { adjusted_fee }

    it 'destroys the adjusted fee' do
      aggregate_failures do
        expect { destroy_service.call }.to change(AdjustedFee, :count).by(-1)
      end
    end

    context 'when adjusted fee is not found' do
      before { adjusted_fee.update!(fee: nil) }

      it 'returns an error' do
        result = destroy_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('adjusted_fee_not_found')
        end
      end
    end

    context 'when fee is not found' do
      let(:fee) { nil }

      it 'returns an error' do
        result = destroy_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('fee_not_found')
        end
      end
    end
  end
end

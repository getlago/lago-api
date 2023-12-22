# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdjustedFees::CreateService, type: :service do
  subject(:create_service) { described_class.new(organization:, fee:, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:fee) { create(:charge_fee) }
  let(:code) { 'tax_code' }
  let(:params) do
    {
      units: 5,
      unit_amount_cents: 1200,
      invoice_display_name: 'new-dis-name',
    }
  end

  describe '#call' do
    before { fee.invoice.draft! }

    context 'when license is premium' do
      around { |test| lago_premium!(&test) }

      it 'creates an adjusted fee' do
        expect { create_service.call }.to change(AdjustedFee, :count).by(1)
      end

      it 'returns adjusted fee in the result' do
        result = create_service.call
        expect(result.adjusted_fee).to be_a(AdjustedFee)
      end

      it 'returns fee in the result' do
        result = create_service.call
        expect(result.fee).to be_a(Fee)
      end

      it 'enqueues the Invoices::RefreshBatchJob' do
        expect { create_service.call }.to have_enqueued_job(Invoices::RefreshBatchJob)
      end

      context 'when invoice is NOT in draft status' do
        before { fee.invoice.finalized! }

        it 'returns forbidden status' do
          result = create_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ForbiddenFailure)
            expect(result.error.code).to eq('feature_unavailable')
          end
        end
      end
    end

    context 'when license is not premium' do
      it 'returns forbidden status' do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ForbiddenFailure)
          expect(result.error.code).to eq('feature_unavailable')
        end
      end
    end
  end
end

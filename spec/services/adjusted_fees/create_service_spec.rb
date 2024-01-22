# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdjustedFees::CreateService, type: :service do
  subject(:create_service) { described_class.new(organization:, fee:, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:fee) { create(:charge_fee) }
  let(:code) { 'tax_code' }
  let(:refresh_service) { instance_double(Invoices::RefreshDraftService) }
  let(:params) do
    {
      units: 5,
      unit_amount_cents: 1200,
      invoice_display_name: 'new-dis-name',
    }
  end

  describe '#call' do
    before do
      fee.invoice.draft!
      allow(Invoices::RefreshDraftService).to receive(:new).with(invoice: fee.invoice).and_return(refresh_service)
      allow(refresh_service).to receive(:call).and_return(BaseService::Result.new)
    end

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

      it 'calls the RefreshDraft service' do
        create_service.call

        expect(Invoices::RefreshDraftService).to have_received(:new)
        expect(refresh_service).to have_received(:call)
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

      context 'when there is invalid charge model but amount is adjusted' do
        let(:percentage_charge) { create(:percentage_charge) }

        before { fee.charge = percentage_charge }

        it 'returns success response' do
          result = create_service.call

          expect(result).to be_success
        end
      end

      context 'when there is invalid charge model and units are adjusted' do
        let(:percentage_charge) { create(:percentage_charge) }
        let(:params) do
          {
            units: 5,
            invoice_display_name: 'new-dis-name',
          }
        end

        before { fee.charge = percentage_charge }

        it 'returns error' do
          result = create_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:charge]).to eq(['invalid_charge_model'])
          end
        end
      end

      context 'when adjusted fee already exists' do
        let(:adjusted_fee) { create(:adjusted_fee, fee:) }

        before { adjusted_fee }

        it 'returns validation error' do
          result = create_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:adjusted_fee]).to eq(['already_exists'])
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

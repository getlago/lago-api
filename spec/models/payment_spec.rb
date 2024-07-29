# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payment, type: :model do
  subject(:payment) { create(:payment) }

  it_behaves_like 'paper_trail traceable'

  it { is_expected.to have_many(:integration_resources) }
  it { is_expected.to belong_to(:payable) }
  it { is_expected.to delegate_method(:customer).to(:payable) }

  describe '#should_sync_payment?' do
    subject(:method_call) { payment.should_sync_payment? }

    let(:payment) { create(:payment, payable: invoice) }
    let(:invoice) { create(:invoice, customer:, organization:, status:) }
    let(:organization) { create(:organization) }

    context 'when invoice is not finalized' do
      let(:status) { %i[draft voided generating].sample }

      context 'without integration customer' do
        let(:customer) { create(:customer, organization:) }

        it 'returns false' do
          expect(method_call).to eq(false)
        end
      end

      context 'with integration customer' do
        let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }
        let(:integration) { create(:netsuite_integration, organization:, sync_payments:) }
        let(:customer) { create(:customer, organization:) }

        before { integration_customer }

        context 'when sync payments is true' do
          let(:sync_payments) { true }

          it 'returns false' do
            expect(method_call).to eq(false)
          end
        end

        context 'when sync payments is false' do
          let(:sync_payments) { false }

          it 'returns false' do
            expect(method_call).to eq(false)
          end
        end
      end
    end

    context 'when invoice is finalized' do
      let(:status) { :finalized }

      context 'without integration customer' do
        let(:customer) { create(:customer, organization:) }

        it 'returns false' do
          expect(method_call).to eq(false)
        end
      end

      context 'with integration customer' do
        let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }
        let(:integration) { create(:netsuite_integration, organization:, sync_payments:) }
        let(:customer) { create(:customer, organization:) }

        before { integration_customer }

        context 'when sync payments is true' do
          let(:sync_payments) { true }

          it 'returns true' do
            expect(method_call).to eq(true)
          end
        end

        context 'when sync payments is false' do
          let(:sync_payments) { false }

          it 'returns false' do
            expect(method_call).to eq(false)
          end
        end
      end
    end
  end
end

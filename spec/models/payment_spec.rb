# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payment, type: :model do
  subject(:payment) { build(:payment, payment_type:, provider_payment_id:, reference:) }

  let(:payment_type) { 'provider' }
  let(:provider_payment_id) { SecureRandom.uuid }
  let(:reference) { nil }

  it_behaves_like 'paper_trail traceable'

  it { is_expected.to have_many(:integration_resources) }
  it { is_expected.to belong_to(:payable) }
  it { is_expected.to delegate_method(:customer).to(:payable) }
  it { is_expected.to validate_presence_of(:payment_type) }

  it do
    expect(subject)
      .to define_enum_for(:payment_type)
      .with_values(Payment::PAYMENT_TYPES)
      .with_prefix(:payment_type)
      .backed_by_column_of_type(:enum)
  end

  describe 'validations' do
    let(:errors) { payment.errors }

    before { payment.valid? }

    describe 'of reference' do
      context 'when payment type is provider' do
        context 'when reference is present' do
          let(:reference) { '123' }

          it 'adds an error' do
            expect(errors.where(:reference, :present)).to be_present
          end
        end

        context 'when reference is not present' do
          it 'does not add an error' do
            expect(errors.where(:reference, :present)).not_to be_present
          end
        end
      end

      context 'when payment type is manual' do
        let(:payment_type) { 'manual' }

        context 'when reference is present' do
          context 'when reference is less than 40 characters' do
            let(:reference) { '123' }

            it 'does not add an error' do
              expect(errors.where(:reference, :blank)).not_to be_present
            end
          end

          context 'when reference is more than 40 characters' do
            let(:reference) { 'a' * 41 }

            it 'adds an error' do
              expect(errors.where(:reference, :too_long)).to be_present
            end
          end
        end
      end
    end
  end

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

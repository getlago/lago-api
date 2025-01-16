# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payment, type: :model do
  subject(:payment) { build(:payment, payable:, payment_type:, provider_payment_id:, reference:, amount_cents:) }

  let(:payable) { create(:invoice, total_amount_cents: 10000) }
  let(:payment_type) { 'provider' }
  let(:provider_payment_id) { SecureRandom.uuid }
  let(:reference) { nil }
  let(:amount_cents) { 200 }

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

    describe 'of max invoice paid amount cents' do
      before { payment.save }

      context 'when payable is an invoice' do
        context 'when payment type is provider' do
          let(:payment_type) { 'provider' }

          context 'when amount cents + total paid amount cents is smaller or equal than invoice total amount cents' do
            let(:payment_request) { create(:payment_request, payment_status: :succeeded) }

            it 'does not add an error' do
              expect(errors.where(:amount_cents, :greater_than)).not_to be_present
            end
          end

          context 'when amount cents + total paid amount cents is greater than invoice total amount cents' do
            let(:amount_cents) { 10001 }

            it 'does not add an error' do
              expect(errors.where(:amount_cents, :greater_than)).not_to be_present
            end
          end
        end

        context 'when payment type is manual' do
          let(:payment_type) { 'manual' }

          context 'when amount cents + total paid amount cents is smaller or equal than invoice total amount cents' do
            let(:payment_request) { create(:payment_request, payment_status: :succeeded) }

            it 'does not add an error' do
              expect(errors.where(:amount_cents, :greater_than)).not_to be_present
            end
          end

          context 'when amount cents + total paid amount cents is greater than invoice total amount cents' do
            let(:amount_cents) { 10001 }

            it 'adds an error' do
              expect(errors.where(:amount_cents, :greater_than)).to be_present
            end
          end
        end
      end
    end

    describe 'of payment request succeeded' do
      context 'when payable is an invoice' do
        context 'when payment type is provider' do
          let(:payment_type) { 'provider' }

          context 'when succeeded payment requests exist' do
            let(:payment_request) { create(:payment_request, payment_status: :succeeded) }

            before do
              create(:payment_request_applied_invoice, payment_request:, invoice: payable)
              payment.save
            end

            it 'does not add an error' do
              expect(errors.where(:base, :payment_request_is_already_succeeded)).not_to be_present
            end
          end

          context 'when no succeeded payment requests exist' do
            before { payment.save }

            it 'does not add an error' do
              expect(errors.where(:base, :payment_request_is_already_succeeded)).not_to be_present
            end
          end
        end

        context 'when payment type is manual' do
          let(:payment_type) { 'manual' }

          context 'when succeeded payment request exist' do
            let(:payment_request) { create(:payment_request, payment_status: 'succeeded') }

            before do
              create(:payment_request_applied_invoice, payment_request:, invoice: payable)
              payment.save
            end

            it 'adds an error' do
              expect(payment.errors.where(:base, :payment_request_is_already_succeeded)).to be_present
            end
          end

          context 'when no succeeded payment requests exist' do
            before { payment.save }

            it 'does not add an error' do
              expect(errors.where(:base, :payment_request_is_already_succeeded)).not_to be_present
            end
          end
        end
      end

      context 'when payable is not an invoice' do
        let(:payable) { create(:payment_request) }

        context 'when payment type is provider' do
          let(:payment_type) { 'provider' }

          before { payment.save }

          it 'does not add an error' do
            expect(errors.where(:base, :payment_request_is_already_succeeded)).not_to be_present
          end
        end

        context 'when payment type is manual' do
          let(:payment_type) { 'manual' }

          before { payment.save }

          it 'does not add an error' do
            expect(errors.where(:base, :payment_request_is_already_succeeded)).not_to be_present
          end
        end
      end
    end

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

        context 'when reference is not present' do
          it 'adds an error' do
            expect(errors[:reference]).to include('value_is_mandatory')
          end
        end

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

  describe ".for_organization" do
    subject(:result) { described_class.for_organization(organization) }

    let(:organization) { create(:organization) }
    let(:invoice) { create(:invoice, organization:) }
    let(:payment_request) { create(:payment_request, organization:) }
    let(:other_org_payment_request) { create(:payment_request) }

    let(:invoice_payment) { create(:payment, payable: invoice) }
    let(:payment_request_payment) { create(:payment, payable: payment_request) }
    let(:other_org_invoice_payment) { create(:payment) }
    let(:other_org_payment_request_payment) { create(:payment, payable: other_org_payment_request) }

    before do
      invoice_payment
      payment_request_payment

      other_org_invoice_payment
      other_org_payment_request_payment
    end

    it "returns organization's payments" do
      payments = subject

      expect(payments).to include(invoice_payment)
      expect(payments).to include(payment_request_payment)
      expect(payments).not_to include(other_org_invoice_payment)
      expect(payments).not_to include(other_org_payment_request_payment)
    end
  end
end

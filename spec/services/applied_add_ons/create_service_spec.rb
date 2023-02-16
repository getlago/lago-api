# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppliedAddOns::CreateService, type: :service do
  subject(:create_service) do
    described_class.new(customer:, add_on:, params:)
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:customer) { create(:customer, organization:) }
  let(:add_on) { create(:add_on, organization:) }

  let(:amount_cents) { nil }
  let(:amount_currency) { nil }
  let(:params) { { amount_cents:, amount_currency: } }

  let(:create_subscription) { customer.present? }

  before do
    create(:active_subscription, customer:) if create_subscription
  end

  describe 'call' do
    let(:create_result) { create_service.call }

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'applied the add-on to the customer' do
      expect { create_result }.to change(AppliedAddOn, :count).by(1)

      expect(create_result.applied_add_on.customer).to eq(customer)
      expect(create_result.applied_add_on.add_on).to eq(add_on)
      expect(create_result.applied_add_on.amount_cents).to eq(add_on.amount_cents)
      expect(create_result.applied_add_on.amount_currency).to eq(add_on.amount_currency)
    end

    it 'enqueues a job to bill the add-on' do
      expect { create_result }.to have_enqueued_job(BillAddOnJob)
    end

    it 'calls SegmentTrackJob' do
      applied_add_on = create_result.applied_add_on

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'applied_add_on_created',
        properties: {
          customer_id: applied_add_on.customer.id,
          addon_code: applied_add_on.add_on.code,
          addon_name: applied_add_on.add_on.name,
        },
      )
    end

    context 'with overridden amount and currency' do
      let(:amount_cents) { 123 }
      let(:amount_currency) { 'EUR' }

      it { expect(create_result.applied_add_on.amount_cents).to eq(123) }
      it { expect(create_result.applied_add_on.amount_currency).to eq('EUR') }

      context 'when currency does not match' do
        let(:amount_currency) { 'NOK' }

        before { customer.update!(currency: 'EUR') }

        it 'fails' do
          aggregate_failures do
            expect(create_result).not_to be_success
            expect(create_result.error).to be_a(BaseService::ValidationFailure)
            expect(create_result.error.messages.keys).to include(:currency)
            expect(create_result.error.messages[:currency]).to include('currencies_does_not_match')
          end
        end
      end
    end

    context 'when customer is not found' do
      let(:customer) { nil }

      it 'returns a not found error' do
        aggregate_failures do
          expect(create_result).not_to be_success
          expect(create_result.error).to be_a(BaseService::NotFoundFailure)
          expect(create_result.error.message).to eq('customer_not_found')
        end
      end
    end

    context 'when add-on is not found' do
      let(:add_on) { nil }

      it 'returns a not found error' do
        aggregate_failures do
          expect(create_result).not_to be_success
          expect(create_result.error).to be_a(BaseService::NotFoundFailure)
          expect(create_result.error.message).to eq('add_on_not_found')
        end
      end
    end

    context 'when currency of an add-on does not match customer currency' do
      let(:add_on) { create(:add_on, organization:, amount_currency: 'NOK') }

      before { customer.update!(currency: 'EUR') }

      it 'fails' do
        aggregate_failures do
          expect(create_result).not_to be_success
          expect(create_result.error).to be_a(BaseService::ValidationFailure)
          expect(create_result.error.messages.keys).to include(:currency)
          expect(create_result.error.messages[:currency]).to include('currencies_does_not_match')
        end
      end
    end

    context 'when customer does not have a currency' do
      let(:create_subscription) { false }
      let(:amount_currency) { 'NOK' }

      before { customer.update!(currency: nil) }

      it 'assigns the add on currency to the customer' do
        create_result

        expect(customer.reload.currency).to eq(amount_currency)
      end
    end
  end
end

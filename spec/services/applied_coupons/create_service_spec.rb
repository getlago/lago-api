# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppliedCoupons::CreateService, type: :service do
  subject(:create_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:customer) { create(:customer, organization: organization) }
  let(:customer_id) { customer.id }

  let(:coupon) { create(:coupon, status: 'active', organization: organization) }
  let(:coupon_id) { coupon.id }

  let(:amount_cents) { nil }
  let(:amount_currency) { nil }

  let(:create_subscription) { customer.present? }

  before do
    create(:active_subscription, customer_id: customer_id) if create_subscription
  end

  describe 'create' do
    let(:create_args) do
      {
        coupon_id: coupon_id,
        customer_id: customer_id,
        amount_cents: amount_cents,
        amount_currency: amount_currency,
        organization_id: organization.id,
      }
    end

    let(:create_result) { create_service.create(**create_args) }

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'applied the coupon to the customer' do
      expect { create_result }.to change(AppliedCoupon, :count).by(1)

      expect(create_result.applied_coupon.customer).to eq(customer)
      expect(create_result.applied_coupon.coupon).to eq(coupon)
      expect(create_result.applied_coupon.amount_cents).to eq(coupon.amount_cents)
      expect(create_result.applied_coupon.amount_currency).to eq(coupon.amount_currency)
    end

    it 'calls SegmentTrackJob' do
      applied_coupon = create_result.applied_coupon

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'applied_coupon_created',
        properties: {
          customer_id: applied_coupon.customer.id,
          coupon_code: applied_coupon.coupon.code,
          coupon_name: applied_coupon.coupon.name,
          organization_id: applied_coupon.coupon.organization_id,
        },
      )
    end

    context 'with overridden amount' do
      let(:amount_cents) { 123 }
      let(:amount_currency) { 'EUR' }

      it { expect(create_result.applied_coupon.amount_cents).to eq(123) }
      it { expect(create_result.applied_coupon.amount_currency).to eq('EUR') }

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
      let(:customer_id) { 'foo' }

      it 'returns a not found error' do
        aggregate_failures do
          expect(create_result).not_to be_success
          expect(create_result.error).to be_a(BaseService::NotFoundFailure)
          expect(create_result.error.message).to eq('customer_not_found')
        end
      end
    end

    context 'when coupon is not found' do
      let(:coupon_id) { 'foo' }

      it 'returns a not found error' do
        aggregate_failures do
          expect(create_result).not_to be_success
          expect(create_result.error).to be_a(BaseService::NotFoundFailure)
          expect(create_result.error.message).to eq('coupon_not_found')
        end
      end
    end

    context 'when coupon is inactive' do
      before { coupon.terminated! }

      it 'returns a not found error' do
        aggregate_failures do
          expect(create_result).not_to be_success
          expect(create_result.error).to be_a(BaseService::NotFoundFailure)
          expect(create_result.error.message).to eq('coupon_not_found')
        end
      end
    end

    context 'when coupon is already applied to the customer' do
      before { create(:applied_coupon, customer: customer, coupon: coupon) }

      it 'fails' do
        aggregate_failures do
          expect(create_result).not_to be_success
          expect(create_result.error).to be_a(BaseService::ValidationFailure)
          expect(create_result.error.messages.keys).to include(:coupon)
          expect(create_result.error.messages[:coupon]).to include('coupon_already_applied')
        end
      end
    end

    context 'when an other coupon is already applied to the customer' do
      let(:other_coupon) { create(:coupon, status: 'active', organization: organization) }

      before { create(:applied_coupon, customer: customer, coupon: other_coupon) }

      it 'fails' do
        aggregate_failures do
          expect(create_result).not_to be_success
          expect(create_result.error).to be_a(BaseService::ValidationFailure)
          expect(create_result.error.messages.keys).to include(:coupon)
          expect(create_result.error.messages[:coupon]).to include('coupon_already_applied')
        end
      end
    end

    context 'when currency of coupon does not match customer currency' do
      let(:coupon) { create(:coupon, status: 'active', organization: organization, amount_currency: 'NOK') }

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

  describe 'create_from_api' do
    let(:coupon_code) { coupon&.code }
    let(:external_customer_id) { customer&.external_id }

    let(:create_args) do
      {
        coupon_code: coupon_code,
        external_customer_id: external_customer_id,
        amount_cents: amount_cents,
        amount_currency: amount_currency,
      }
    end

    let(:create_result) do
      create_service.create_from_api(
        organization: organization,
        args: create_args,
      )
    end

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'applies the coupon to the customer' do
      expect { create_result }.to change(AppliedCoupon, :count).by(1)

      expect(create_result.applied_coupon.customer).to eq(customer)
      expect(create_result.applied_coupon.coupon).to eq(coupon)
      expect(create_result.applied_coupon.amount_cents).to eq(coupon.amount_cents)
      expect(create_result.applied_coupon.amount_currency).to eq(coupon.amount_currency)
    end

    it 'calls SegmentTrackJob' do
      applied_coupon = create_result.applied_coupon

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'applied_coupon_created',
        properties: {
          customer_id: applied_coupon.customer.id,
          coupon_code: applied_coupon.coupon.code,
          coupon_name: applied_coupon.coupon.name,
          organization_id: applied_coupon.coupon.organization_id,
        },
      )
    end

    context 'with overridden amount' do
      let(:amount_cents) { 123 }
      let(:amount_currency) { 'EUR' }

      it { expect(create_result.applied_coupon.amount_cents).to eq(123) }
      it { expect(create_result.applied_coupon.amount_currency).to eq('EUR') }

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
      let(:external_customer_id) { 'foo' }

      it 'returns a not found error' do
        aggregate_failures do
          expect(create_result).not_to be_success
          expect(create_result.error).to be_a(BaseService::NotFoundFailure)
          expect(create_result.error.message).to eq('customer_not_found')
        end
      end
    end

    context 'when coupon is not found' do
      let(:coupon_code) { 'foo' }

      it 'returns a not found error' do
        aggregate_failures do
          expect(create_result).not_to be_success
          expect(create_result.error).to be_a(BaseService::NotFoundFailure)
          expect(create_result.error.message).to eq('coupon_not_found')
        end
      end
    end

    context 'when coupon is inactive' do
      before { coupon.terminated! }

      it 'returns a not found error' do
        aggregate_failures do
          expect(create_result).not_to be_success
          expect(create_result.error).to be_a(BaseService::NotFoundFailure)
          expect(create_result.error.message).to eq('coupon_not_found')
        end
      end
    end

    context 'when coupon is already applied to the customer' do
      before { create(:applied_coupon, customer: customer, coupon: coupon) }

      it 'fails' do
        aggregate_failures do
          expect(create_result).not_to be_success
          expect(create_result.error).to be_a(BaseService::ValidationFailure)
          expect(create_result.error.messages.keys).to include(:coupon)
          expect(create_result.error.messages[:coupon]).to include('coupon_already_applied')
        end
      end
    end

    context 'when currency of coupon does not match customer currency' do
      let(:coupon) { create(:coupon, status: 'active', organization: organization, amount_currency: 'NOK') }

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

      it 'assigns the coupon currency to the customer' do
        create_result

        expect(customer.reload.currency).to eq(amount_currency)
      end
    end
  end
end

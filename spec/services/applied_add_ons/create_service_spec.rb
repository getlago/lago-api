# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppliedAddOns::CreateService, type: :service do
  subject(:create_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:customer) { create(:customer, organization: organization) }
  let(:customer_id) { customer.id }

  let(:add_on) { create(:add_on, organization: organization) }
  let(:add_on_id) { add_on.id }

  let(:amount_cents) { nil }
  let(:amount_currency) { nil }

  before do
    create(:active_subscription, customer_id: customer_id) if customer
  end

  describe 'create' do
    let(:create_args) do
      {
        add_on_id: add_on_id,
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
          addon_name: applied_add_on.add_on.name
        }
      )
    end

    context 'with overridden amount and currency' do
      let(:amount_cents) { 123 }
      let(:amount_currency) { 'EUR' }

      it { expect(create_result.applied_add_on.amount_cents).to eq(123) }
      it { expect(create_result.applied_add_on.amount_currency).to eq('EUR') }

      context 'when currency does not match' do
        let(:amount_currency) { 'NOK' }

        it { expect(create_result).not_to be_success }
        it { expect(create_result.error).to eq('currencies_does_not_match') }
      end
    end

    context 'when customer is not found' do
      let(:customer) { nil }
      let(:customer_id) { 'foo' }

      it { expect(create_result).not_to be_success }
      it { expect(create_result.error_code).to eq('missing_argument') }
      it { expect(create_result.error).to eq('unable_to_find_customer') }
    end

    context 'when add-on is not found' do
      let(:add_on_id) { 'foo' }

      it { expect(create_result).not_to be_success }
      it { expect(create_result.error_code).to eq('missing_argument') }
      it { expect(create_result.error).to eq('add_on_does_not_exist') }
    end

    context 'when customer does not have a subscription' do
      before { customer.active_subscription.terminated! }

      it { expect(create_result).not_to be_success }
      it { expect(create_result.error).to eq('no_active_subscription') }
    end

    context 'when currency of an add-on does not match customer currency' do
      let(:add_on) { create(:add_on, organization: organization, amount_currency: 'NOK') }

      it { expect(create_result).not_to be_success }
      it { expect(create_result.error).to eq('currencies_does_not_match') }
    end
  end

  describe 'create_from_api' do
    let(:add_on_code) { add_on&.code }
    let(:external_customer_id) { customer&.external_id }

    let(:create_args) do
      {
        add_on_code: add_on_code,
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
          addon_name: applied_add_on.add_on.name
        }
      )
    end

    context 'with overridden amount' do
      let(:amount_cents) { 123 }
      let(:amount_currency) { 'EUR' }

      it { expect(create_result.applied_add_on.amount_cents).to eq(123) }
      it { expect(create_result.applied_add_on.amount_currency).to eq('EUR') }

      context 'when currency does not match' do
        let(:amount_currency) { 'NOK' }

        it { expect(create_result).not_to be_success }
        it { expect(create_result.error).to eq('currencies_does_not_match') }
      end
    end

    context 'when customer is not found' do
      let(:customer) { nil }
      let(:external_customer_id) { 'foo' }

      it { expect(create_result).not_to be_success }
      it { expect(create_result.error_code).to eq('missing_argument') }
      it { expect(create_result.error).to eq('unable_to_find_customer') }
    end

    context 'when add-on is not found' do
      let(:add_on_code) { 'foo' }

      it { expect(create_result).not_to be_success }
      it { expect(create_result.error_code).to eq('missing_argument') }
      it { expect(create_result.error).to eq('add_on_does_not_exist') }
    end

    context 'when customer does not have a subscription' do
      before { customer.active_subscription.terminated! }

      it { expect(create_result).not_to be_success }
      it { expect(create_result.error).to eq('no_active_subscription') }
    end

    context 'when currency of add-on does not match customer currency' do
      let(:add_on) { create(:add_on, organization: organization, amount_currency: 'NOK') }

      it { expect(create_result).not_to be_success }
      it { expect(create_result.error).to eq('currencies_does_not_match') }
    end
  end
end

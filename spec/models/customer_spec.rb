# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Customer, type: :model do
  let(:organization) { create(:organization) }

  describe 'validations' do
    subject(:customer) do
      described_class.new(
        organization: organization,
        external_id: external_id,
      )
    end

    let(:external_id) { SecureRandom.uuid }

    it 'validates the country' do
      expect(customer).to be_valid

      customer.country = 'fr'
      expect(customer).to be_valid

      customer.country = 'foo'
      expect(customer).not_to be_valid

      customer.country = ''
      expect(customer).not_to be_valid
    end
  end

  describe 'applicable_vat_rate' do
    subject(:customer) do
      described_class.new(
        organization: organization,
        vat_rate: 12,
      )
    end

    it 'returns the customer vat_rate' do
      expect(customer.applicable_vat_rate).to eq(12)
    end

    context 'when customer does not have a vat_rate' do
      let(:organization_vat_rate) { 14 }

      before do
        customer.vat_rate = nil
        customer.organization.vat_rate = organization_vat_rate
      end

      it 'returns the organization vat_rate' do
        expect(customer.applicable_vat_rate).to eq(14)
      end

      context 'when organization does not have a vat_rate' do
        let(:organization_vat_rate) { nil }

        it { expect(customer.applicable_vat_rate).to eq(0) }
      end
    end
  end

  describe 'slug' do
    let(:organization) { create(:organization, name: 'LAGO') }

    let(:customer) do
      build(
        :customer,
        organization: organization,
      )
    end

    it 'assigns a sequential id and a slug to a new customer' do
      customer.save
      organization_id_substring = organization.id.last(4).upcase

      aggregate_failures do
        expect(customer).to be_valid
        expect(customer.sequential_id).to eq(1)
        expect(customer.slug).to eq("LAG-#{organization_id_substring}-001")
      end
    end
  end

  describe 'deletable?' do
    let(:customer) { create(:customer) }

    it { expect(customer).to be_deletable }

    context 'when attached to a subscription' do
      before { create(:subscription, customer: customer) }

      it { expect(customer).not_to be_deletable }
    end

    context 'when attached to an add-on' do
      before { create(:applied_add_on, customer: customer) }

      it { expect(customer).not_to be_deletable }
    end

    context 'when attached to a coupon' do
      before { create(:applied_coupon, customer: customer) }

      it { expect(customer).not_to be_deletable }
    end

    context 'when attached to a wallet' do
      before { create(:wallet, customer: customer) }

      it { expect(customer).not_to be_deletable }
    end
  end

  describe '.editable_subscriptions' do
    let(:customer) { create(:customer) }
    let(:subscription) { create(:active_subscription, customer: customer) }
    let(:second_subscription) { create(:pending_subscription, customer: customer) }
    let(:third_subscription) { create(:pending_subscription, customer: customer, previous_subscription: subscription) }

    before do
      subscription
      second_subscription
      third_subscription
    end

    it 'returns only active and pending subscriptions that are NOT downgraded' do
      result = customer.editable_subscriptions

      aggregate_failures do
        expect(result.count).to eq(2)
        expect(result.pluck(:id)).not_to include(third_subscription.id)
      end
    end
  end
end

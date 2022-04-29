# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Customer, type: :model do
  let(:organization) { create(:organization) }

  describe 'validations' do
    subject(:customer) do
      described_class.new(
        organization: organization,
        customer_id: customer_id,
      )
    end

    let(:customer_id) { SecureRandom.uuid }

    it 'validates the country' do
      expect(customer).to be_valid

      customer.country = 'fr'
      expect(customer).to be_valid

      customer.country = 'foo'
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
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomersService, type: :service do
  subject { described_class.new }

  let(:organization) { create(:organization) }

  describe 'create' do
    let(:create_args) do
      {
        external_id: SecureRandom.uuid,
        name: 'Foo Bar'
      }
    end

    it 'creates a new customer' do
      result = subject.create(
        organization: organization,
        params: create_args
      )

      expect(result).to be_success

      customer = result.customer
      expect(customer.id).to be_present
      expect(customer.organization_id).to eq(organization.id)
      expect(customer.external_id).to eq(create_args[:external_id])
      expect(customer.name).to eq(create_args[:name])
    end

    context 'whin customer already exists' do
      let!(:customer) do
        create(:customer, organization: organization, external_id: create_args[:external_id])
      end

      it 'updates the customer' do
        result = subject.create(
          organization: organization,
          params: create_args
        )

        expect(result).to be_success
        expect(result.customer).to eq(customer)
        expect(result.customer.name).to eq(create_args[:name])
      end
    end

    context 'with validation error' do
      let(:create_args) do
        {
          name: 'Foo Bar'
        }
      end

      it 'return a failed result' do
        result = subject.create(
          organization: organization,
          params: create_args
        )

        expect(result).to_not be_success
      end
    end
  end
end

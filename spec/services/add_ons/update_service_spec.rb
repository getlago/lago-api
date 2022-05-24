# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AddOns::UpdateService, type: :service do
  subject(:update_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:add_on) { create(:add_on, organization: organization) }

  describe 'update' do
    before { add_on }

    let(:update_args) do
      {
        id: add_on.id,
        name: 'new name',
        code: 'code',
        description: 'desc',
        amount_cents: 100,
        amount_currency: 'EUR'
      }
    end

    it 'updates the add-on' do
      result = update_service.update(**update_args)

      expect(result).to be_success

      aggregate_failures do
        expect(result.add_on.name).to eq('new name')
        expect(result.add_on.description).to eq('desc')
        expect(result.add_on.amount_cents).to eq(100)
        expect(result.add_on.amount_currency).to eq('EUR')
      end
    end

    context 'with validation error' do
      let(:update_args) do
        {
          id: add_on.id,
          name: nil,
          code: 'code',
          amount_cents: 100,
          amount_currency: 'EUR'
        }
      end

      it 'returns an error' do
        result = update_service.update(**update_args)

        expect(result).to_not be_success
        expect(result.error_code).to eq('unprocessable_entity')
      end
    end
  end
end

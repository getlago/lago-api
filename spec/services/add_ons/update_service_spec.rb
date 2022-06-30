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

  describe 'update_from_api' do
    let(:add_on) { create(:add_on, organization: organization) }
    let(:name) { 'New Add On' }
    let(:update_args) do
      {
        name: name,
        code: 'code',
        description: 'desc',
        amount_cents: 100,
        amount_currency: 'EUR'
      }
    end

    it 'updates the add-on' do
      result = subject.update_from_api(
        organization: organization,
        code: add_on.code,
        params: update_args
      )

      aggregate_failures do
        expect(result).to be_success

        add_on_result = result.add_on
        expect(add_on_result.id).to eq(add_on.id)
        expect(add_on_result.name).to eq(update_args[:name])
        expect(add_on_result.code).to eq(update_args[:code])
        expect(add_on_result.description).to eq(update_args[:description])
      end
    end

    context 'with validation errors' do
      let(:name) { nil }

      it 'returns an error' do
        result = subject.update_from_api(
          organization: organization,
          code: add_on.code,
          params: update_args
        )

        expect(result).to_not be_success
        expect(result.error_code).to eq('unprocessable_entity')
      end
    end

    context 'when add-on is not found' do
      it 'returns an error' do
        result = subject.update_from_api(
          organization: organization,
          code: 'fake_code12345',
          params: update_args
        )

        expect(result).to_not be_success
        expect(result.error_code).to eq('not_found')
      end
    end
  end
end

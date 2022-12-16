# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::ValidateService, type: :service do
  subject(:validate_service) { described_class.new(result, **args) }

  let(:result) { BaseService::Result.new }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization: organization) }
  let(:plan) { create(:plan, organization: organization) }
  let(:subscription_at) { '2022-07-07T00:00:00Z' }

  let(:args) do
    {
      customer: customer,
      plan: plan,
      subscription_at: subscription_at,
    }
  end

  describe '.valid?' do
    it 'returns true' do
      expect(validate_service).to be_valid
    end

    context 'when customer does not exist' do
      let(:customer) { nil }

      it 'returns false and result has errors' do
        expect(validate_service).not_to be_valid

        aggregate_failures do
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq('customer_not_found')
        end
      end
    end

    context 'when plan does not exist' do
      let(:plan) { nil }

      it 'returns false and result has errors' do
        expect(validate_service).not_to be_valid

        aggregate_failures do
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq('plan_not_found')
        end
      end
    end

    context 'with invalid subscription_at' do
      context 'when string cannot be parsed to date' do
        let(:subscription_at) { 'invalid' }

        it 'returns false and result has errors' do
          expect(validate_service).not_to be_valid
          expect(result.error.messages[:subscription_at]).to eq(['invalid_date'])
        end
      end

      context 'when subscription_at is integer' do
        let(:subscription_at) { 123 }

        it 'returns false and result has errors' do
          expect(validate_service).not_to be_valid
          expect(result.error.messages[:subscription_at]).to eq(['invalid_date'])
        end
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallets::ValidateService, type: :service do
  subject(:validate_service) { described_class.new(result, **args) }

  let(:result) { BaseService::Result.new }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:customer_id) { customer.external_id }
  let(:paid_credits) { '1.00' }
  let(:granted_credits) { '0.00' }
  let(:expiration_at) { (Time.current + 1.year).iso8601 }
  let(:args) do
    {
      customer:,
      organization_id: organization.id,
      paid_credits:,
      granted_credits:,
      expiration_at:,
    }
  end

  before { subscription }

  describe '.valid?' do
    it 'returns true' do
      expect(validate_service).to be_valid
    end

    context 'when customer does not exist' do
      let(:args) do
        {
          customer: nil,
          organization_id: organization.id,
          paid_credits:,
          granted_credits:,
        }
      end

      it 'returns false and result has errors' do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:customer]).to eq(['customer_not_found'])
      end
    end

    context 'when customer already has a wallet' do
      before { create(:wallet, customer:) }

      it 'returns false and result has errors' do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:customer]).to eq(['wallet_already_exists'])
      end
    end

    context 'with invalid paid_credits' do
      let(:paid_credits) { 'foobar' }

      it 'returns false and result has errors' do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:paid_credits]).to eq(['invalid_paid_credits'])
      end
    end

    context 'with invalid granted_credits' do
      let(:granted_credits) { 'foobar' }

      it 'returns false and result has errors' do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:granted_credits]).to eq(['invalid_granted_credits'])
      end
    end

    context 'with invalid expiration_at' do
      context 'when string cannot be parsed to date' do
        let(:expiration_at) { 'invalid' }

        it 'returns false and result has errors' do
          expect(validate_service).not_to be_valid
          expect(result.error.messages[:expiration_at]).to eq(['invalid_date'])
        end
      end

      context 'when expiration_at is integer' do
        let(:expiration_at) { 123 }

        it 'returns false and result has errors' do
          expect(validate_service).not_to be_valid
          expect(result.error.messages[:expiration_at]).to eq(['invalid_date'])
        end
      end

      context 'when expiration_at is less than current time' do
        let(:expiration_at) { (Time.current - 1.year).iso8601 }

        it 'returns false and result has errors' do
          expect(validate_service).not_to be_valid
          expect(result.error.messages[:expiration_at]).to eq(['invalid_date'])
        end
      end
    end

    context 'with recurring transaction rules' do
      let(:rules) do
        [
          {
            rule_type: 'interval',
            interval: 'monthly',
          },
          {
            rule_type: 'threshold',
            threshold_credits: '1.0',
          },
        ]
      end
      let(:args) do
        {
          customer:,
          organization_id: organization.id,
          paid_credits:,
          granted_credits:,
          recurring_transaction_rules: rules,
        }
      end

      it 'returns false and result has errors' do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:recurring_transaction_rules]).to eq(['invalid_number_of_recurring_rules'])
      end

      context 'when invalid interval' do
        let(:rules) do
          [
            {
              rule_type: 'interval',
              interval: 'invalid',
            },
          ]
        end

        it 'returns false and result has errors' do
          expect(validate_service).not_to be_valid
          expect(result.error.messages[:recurring_transaction_rules]).to eq(['invalid_recurring_rule'])
        end
      end

      context 'when invalid threshold credits' do
        let(:rules) do
          [
            {
              rule_type: 'threshold',
              threshold_credits: 'invalid',
            },
          ]
        end

        it 'returns false and result has errors' do
          expect(validate_service).not_to be_valid
          expect(result.error.messages[:recurring_transaction_rules]).to eq(['invalid_recurring_rule'])
        end
      end
    end
  end
end

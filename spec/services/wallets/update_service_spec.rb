# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallets::UpdateService, type: :service do
  subject(:update_service) { described_class.new(wallet:, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:wallet) { create(:wallet, customer:) }
  let(:expiration_at) { (Time.current + 1.year).iso8601 }

  describe '#call' do
    before do
      subscription
      wallet
    end

    let(:params) do
      {
        id: wallet&.id,
        name: 'new name',
        expiration_at:
      }
    end

    it 'updates the wallet' do
      result = update_service.call
      expect(result).to be_success

      aggregate_failures do
        expect(result.wallet.name).to eq('new name')
        expect(result.wallet.expiration_at.iso8601).to eq(expiration_at)
      end
    end

    it "calls Wallets::Balance::RefreshOngoingService" do
      allow(Wallets::Balance::RefreshOngoingService).to receive(:call)
      update_service.call
      expect(Wallets::Balance::RefreshOngoingService).to have_received(:call).with(wallet:)
    end

    context 'when wallet is not found' do
      let(:wallet) { nil }

      it 'returns an error' do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('wallet_not_found')
      end
    end

    context 'with invalid expiration_at' do
      context 'when string cannot be parsed to date' do
        let(:expiration_at) { 'invalid' }

        it 'returns false and result has errors' do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages[:expiration_at]).to eq(['invalid_date'])
        end
      end

      context 'when expiration_at is integer' do
        let(:expiration_at) { 123 }

        it 'returns false and result has errors' do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages[:expiration_at]).to eq(['invalid_date'])
        end
      end

      context 'when expiration_at is less than current time' do
        let(:expiration_at) { (Time.current - 1.year).iso8601 }

        it 'returns false and result has errors' do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages[:expiration_at]).to eq(['invalid_date'])
        end
      end
    end

    context 'with recurring transaction rules' do
      around { |test| lago_premium!(&test) }

      let(:recurring_transaction_rule) { create(:recurring_transaction_rule, wallet:) }
      let(:rules) do
        [
          {
            trigger: 'interval',
            interval: 'weekly',
            paid_credits: '105',
            granted_credits: '105'
          }
        ]
      end
      let(:params) do
        {
          id: wallet.id,
          name: 'new name',
          expiration_at:,
          recurring_transaction_rules: rules
        }
      end

      before { recurring_transaction_rule }

      it 'creates a new rule and removes the old one' do
        result = update_service.call

        aggregate_failures do
          expect(result).to be_success

          rule = result.wallet.reload.recurring_transaction_rules.first

          expect(result.wallet.reload.recurring_transaction_rules.count).to eq(1)
          expect(rule.id).not_to eq(recurring_transaction_rule.id)
          expect(rule.trigger).to eq('interval')
          expect(rule.interval).to eq('weekly')
          expect(rule.threshold_credits).to eq(0.0)
          expect(rule.paid_credits).to eq(105.0)
          expect(rule.granted_credits).to eq(105.0)
        end
      end

      context 'when editing existing interval rule' do
        let(:rules) do
          [
            {
              lago_id: recurring_transaction_rule.id,
              trigger: 'interval',
              interval: 'weekly',
              paid_credits: '105',
              granted_credits: '105'
            }
          ]
        end

        it 'updates the rule' do
          result = update_service.call

          aggregate_failures do
            expect(result).to be_success

            rule = result.wallet.reload.recurring_transaction_rules.first

            expect(result.wallet.reload.recurring_transaction_rules.count).to eq(1)
            expect(rule.id).to eq(recurring_transaction_rule.id)
            expect(rule.trigger).to eq('interval')
            expect(rule.interval).to eq('weekly')
            expect(rule.threshold_credits).to eq(0.0)
            expect(rule.paid_credits).to eq(105.0)
            expect(rule.granted_credits).to eq(105.0)
          end
        end
      end

      context 'when changing the rule into threshold one' do
        let(:rules) do
          [
            {
              lago_id: recurring_transaction_rule.id,
              trigger: 'threshold',
              threshold_credits: '205',
              paid_credits: '105',
              granted_credits: '105'
            }
          ]
        end

        it 'updates the rule' do
          result = update_service.call

          expect(result).to be_success

          rule = result.wallet.reload.recurring_transaction_rules.first

          aggregate_failures do
            expect(result.wallet.reload.recurring_transaction_rules.count).to eq(1)
            expect(rule.id).to eq(recurring_transaction_rule.id)
            expect(rule.trigger).to eq('threshold')
            expect(rule.threshold_credits).to eq(205.0)
            expect(rule.paid_credits).to eq(105.0)
            expect(rule.granted_credits).to eq(105.0)
          end
        end
      end

      context 'when removing the rule' do
        let(:rules) do
          []
        end

        it 'sanitizes rules successfully' do
          result = update_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.wallet.reload.recurring_transaction_rules.count).to eq(0)
          end
        end
      end

      context 'when number of rules is incorrect' do
        let(:rules) do
          [
            {
              trigger: 'interval',
              interval: 'monthly',
              paid_credits: '105',
              granted_credits: '105'
            },
            {
              trigger: 'threshold',
              threshold_credits: '1.0',
              paid_credits: '105',
              granted_credits: '105'
            }
          ]
        end

        it 'returns an error' do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages[:recurring_transaction_rules])
            .to eq(['invalid_number_of_recurring_rules'])
        end
      end

      context 'when trigger is invalid' do
        let(:rules) do
          [
            {
              trigger: 'invalid',
              interval: 'monthly',
              paid_credits: '105',
              granted_credits: '105'
            }
          ]
        end

        it 'returns an error' do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages[:recurring_transaction_rules]).to eq(['invalid_recurring_rule'])
        end
      end

      context 'when threshold credits value is invalid' do
        let(:rules) do
          [
            {
              trigger: 'threshold',
              threshold_credits: 'abc',
              paid_credits: '105',
              granted_credits: '105'
            }
          ]
        end

        it 'returns an error' do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages[:recurring_transaction_rules]).to eq(['invalid_recurring_rule'])
        end
      end
    end
  end
end

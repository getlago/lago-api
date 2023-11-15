# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallets::UpdateService, type: :service do
  subject(:update_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:wallet) { create(:wallet, customer:) }

  describe 'update' do
    before do
      subscription
      wallet
    end

    let(:update_args) do
      {
        id: wallet.id,
        name: 'new name',
        expiration_at: DateTime.parse('2022-01-01 23:59:59'),
      }
    end

    it 'updates the wallet' do
      result = update_service.update(wallet:, args: update_args)

      expect(result).to be_success

      aggregate_failures do
        expect(result.wallet.name).to eq('new name')
        expect(result.wallet.expiration_at.iso8601).to eq('2022-01-01T23:59:59Z')
      end
    end

    context 'when wallet is not found' do
      let(:update_args) do
        {
          id: '123456',
          name: 'new name',
          expiration_date: '2022-01-01',
        }
      end

      it 'returns an error' do
        result = update_service.update(wallet: nil, args: update_args)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('wallet_not_found')
      end
    end

    context 'with recurring transaction rules' do
      around { |test| lago_premium!(&test) }

      let(:recurring_transaction_rule) { create(:recurring_transaction_rule, wallet:) }
      let(:rules) do
        [
          {
            rule_type: 'interval',
            interval: 'weekly',
            paid_credits: '105',
            granted_credits: '105',
          },
        ]
      end
      let(:update_args) do
        {
          id: wallet.id,
          name: 'new name',
          expiration_at: DateTime.parse('2022-01-01 23:59:59'),
          recurring_transaction_rules: rules,
        }
      end

      before { recurring_transaction_rule }

      it 'creates a new rule and removes the old one' do
        result = update_service.update(wallet:, args: update_args)

        aggregate_failures do
          expect(result).to be_success

          rule = result.wallet.reload.recurring_transaction_rules.first

          expect(result.wallet.reload.recurring_transaction_rules.count).to eq(1)
          expect(rule.id).not_to eq(recurring_transaction_rule.id)
          expect(rule.rule_type).to eq('interval')
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
              rule_type: 'interval',
              interval: 'weekly',
              paid_credits: '105',
              granted_credits: '105',
            },
          ]
        end

        it 'updates the rule' do
          result = update_service.update(wallet:, args: update_args)

          aggregate_failures do
            expect(result).to be_success

            rule = result.wallet.reload.recurring_transaction_rules.first

            expect(result.wallet.reload.recurring_transaction_rules.count).to eq(1)
            expect(rule.id).to eq(recurring_transaction_rule.id)
            expect(rule.rule_type).to eq('interval')
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
              rule_type: 'threshold',
              threshold_credits: '205',
              paid_credits: '105',
              granted_credits: '105',
            },
          ]
        end

        it 'updates the rule' do
          result = update_service.update(wallet:, args: update_args)

          expect(result).to be_success

          rule = result.wallet.reload.recurring_transaction_rules.first

          aggregate_failures do
            expect(result.wallet.reload.recurring_transaction_rules.count).to eq(1)
            expect(rule.id).to eq(recurring_transaction_rule.id)
            expect(rule.rule_type).to eq('threshold')
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
          result = update_service.update(wallet:, args: update_args)

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
              rule_type: 'interval',
              interval: 'monthly',
            },
            {
              rule_type: 'threshold',
              threshold_credits: '1.0',
            },
          ]
        end

        it 'returns an error' do
          result = update_service.update(wallet:, args: update_args)

          expect(result).not_to be_success
          expect(result.error.messages[:recurring_transaction_rules])
            .to eq(['invalid_number_of_recurring_rules'])
        end
      end

      context 'when rule type is invalid' do
        let(:rules) do
          [
            {
              rule_type: 'invalid',
              interval: 'monthly',
            },
          ]
        end

        it 'returns an error' do
          result = update_service.update(wallet:, args: update_args)

          expect(result).not_to be_success
          expect(result.error.messages[:recurring_transaction_rules]).to eq(['invalid_recurring_rule'])
        end
      end

      context 'when threshold credits value is invalid' do
        let(:rules) do
          [
            {
              rule_type: 'threshold',
              threshold_credits: 'abc',
            },
          ]
        end

        it 'returns an error' do
          result = update_service.update(wallet:, args: update_args)

          expect(result).not_to be_success
          expect(result.error.messages[:recurring_transaction_rules]).to eq(['invalid_recurring_rule'])
        end
      end
    end
  end
end

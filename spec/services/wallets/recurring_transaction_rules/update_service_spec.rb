# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallets::RecurringTransactionRules::UpdateService do
  subject(:update_service) { described_class.new(wallet:, params:) }

  let(:wallet) { create(:wallet) }
  let(:recurring_transaction_rule) { create(:recurring_transaction_rule, wallet:) }
  let(:params) do
    [
      {
        lago_id: recurring_transaction_rule.id,
        trigger: 'interval',
        interval: 'weekly',
        paid_credits: '105',
        granted_credits: '105'
      },
    ]
  end

  describe '#call' do
    before { recurring_transaction_rule }

    it 'updates existing recurring transaction rule' do
      result = update_service.call

      rule = result.wallet.reload.recurring_transaction_rules.first

      aggregate_failures do
        expect(result.wallet.reload.recurring_transaction_rules.count).to eq(1)
        expect(rule.id).to eq(recurring_transaction_rule.id)
        expect(rule.trigger).to eq('interval')
        expect(rule.interval).to eq('weekly')
        expect(rule.threshold_credits).to eq(0.0)
        expect(rule.paid_credits).to eq(105.0)
        expect(rule.granted_credits).to eq(105.0)
      end
    end

    context 'with added rule without id' do
      let(:params) do
        [
          {
            trigger: 'interval',
            interval: 'weekly',
            paid_credits: '105',
            granted_credits: '105'
          },
        ]
      end

      it 'creates new recurring transaction rule and removes existing' do
        result = update_service.call

        rule = result.wallet.reload.recurring_transaction_rules.first

        aggregate_failures do
          expect(result.wallet.reload.recurring_transaction_rules.count).to eq(1)
          expect(rule.id).not_to eq(recurring_transaction_rule.id)
          expect(rule.trigger).to eq('interval')
          expect(rule.interval).to eq('weekly')
          expect(rule.threshold_credits).to eq(0.0)
          expect(rule.paid_credits).to eq(105.0)
          expect(rule.granted_credits).to eq(105.0)
        end
      end
    end

    context 'when empty array is sent as argument' do
      let(:params) do
        []
      end

      it 'sanitizes not needed rules' do
        result = update_service.call

        expect(result.wallet.reload.recurring_transaction_rules.count).to eq(0)
      end
    end
  end
end

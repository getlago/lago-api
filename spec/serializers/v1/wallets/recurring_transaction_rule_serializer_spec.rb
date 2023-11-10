# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::Wallets::RecurringTransactionRuleSerializer do
  subject(:serializer) { described_class.new(recurring_transaction_rule, root_name: 'recurring_transaction_rule') }

  let(:recurring_transaction_rule) { create(:recurring_transaction_rule) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['recurring_transaction_rule']['lago_id']).to eq(recurring_transaction_rule.id)
      expect(result['recurring_transaction_rule']['rule_type']).to eq(recurring_transaction_rule.rule_type)
      expect(result['recurring_transaction_rule']['interval']).to eq(recurring_transaction_rule.interval)
      expect(result['recurring_transaction_rule']['paid_credits']).to eq(recurring_transaction_rule.paid_credits.to_s)
      expect(result['recurring_transaction_rule']['created_at']).to eq(recurring_transaction_rule.created_at.iso8601)
      expect(result['recurring_transaction_rule']['threshold_credits'])
        .to eq(recurring_transaction_rule.threshold_credits.to_s)
      expect(result['recurring_transaction_rule']['granted_credits'])
        .to eq(recurring_transaction_rule.granted_credits.to_s)
    end
  end
end

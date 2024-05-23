# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::Wallets::RecurringTransactionRuleSerializer do
  subject(:serializer) { described_class.new(recurring_transaction_rule, root_name: 'recurring_transaction_rule') }

  let(:recurring_transaction_rule) { create(:recurring_transaction_rule) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    expect(result["recurring_transaction_rule"]).to include(
      "lago_id" => recurring_transaction_rule.id,
      "method" => recurring_transaction_rule.method,
      "trigger" => recurring_transaction_rule.trigger,
      "interval" => recurring_transaction_rule.interval,
      "paid_credits" => recurring_transaction_rule.paid_credits.to_s,
      "target_ongoing_balance" => recurring_transaction_rule.target_ongoing_balance,
      "threshold_credits" => recurring_transaction_rule.threshold_credits.to_s,
      "granted_credits" => recurring_transaction_rule.granted_credits.to_s,
      "created_at" => recurring_transaction_rule.created_at.iso8601
    )
  end
end

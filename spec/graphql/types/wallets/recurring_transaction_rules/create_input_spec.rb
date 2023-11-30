# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Wallets::RecurringTransactionRules::CreateInput do
  subject { described_class }

  it { is_expected.to accept_argument(:interval).of_type('RecurringTransactionIntervalEnum') }
  it { is_expected.to accept_argument(:rule_type).of_type('RecurringTransactionRuleTypeEnum!') }
  it { is_expected.to accept_argument(:threshold_credits).of_type('String') }
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Wallets::RecurringTransactionRules::UpdateInput do
  subject { described_class }

  it { is_expected.to accept_argument(:interval).of_type('RecurringTransactionIntervalEnum') }
  it { is_expected.to accept_argument(:method).of_type('RecurringTransactionMethodEnum') }
  it { is_expected.to accept_argument(:trigger).of_type('RecurringTransactionTriggerEnum') }
  it { is_expected.to accept_argument(:threshold_credits).of_type('String') }
  it { is_expected.to accept_argument(:lago_id).of_type('ID') }
  it { is_expected.to accept_argument(:paid_credits).of_type('String') }
  it { is_expected.to accept_argument(:granted_credits).of_type('String') }
end

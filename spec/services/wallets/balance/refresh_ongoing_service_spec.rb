# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallets::Balance::RefreshOngoingService, type: :service do
  subject(:refresh_service) { described_class.new(wallet:) }

  let(:wallet) do
    create(
      :wallet,
      customer:,
      balance_cents: 1000,
      ongoing_balance_cents: 800,
      ongoing_usage_balance_cents: 200,
      credits_balance: 10.0,
      credits_ongoing_balance: 8.0,
      credits_ongoing_usage_balance: 2.0
    )
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:first_subscription) do
    create(:subscription, organization:, customer:, started_at: Time.zone.now - 2.years)
  end
  let(:second_subscription) do
    create(:subscription, organization:, customer:, started_at: Time.zone.now - 1.year)
  end
  let(:timestamp) { Time.current }
  let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }

  let(:first_charge) do
    create(
      :standard_charge,
      plan: first_subscription.plan,
      billable_metric:,
      properties: {amount: '3'}
    )
  end
  let(:second_charge) do
    create(
      :standard_charge,
      plan: second_subscription.plan,
      billable_metric:,
      properties: {amount: '5'}
    )
  end

  let(:events) do
    create_list(
      :event,
      2,
      organization: wallet.organization,
      subscription: first_subscription,
      customer: first_subscription.customer,
      code: billable_metric.code,
      timestamp:
    ).push(
      create(
        :event,
        organization: wallet.organization,
        subscription: second_subscription,
        customer: second_subscription.customer,
        code: billable_metric.code,
        timestamp:
      )
    )
  end

  before do
    first_charge
    second_charge
    wallet
    events
  end

  describe '.call' do
    it 'updates wallet ongoing balance' do
      expect { refresh_service.call }
        .to change(wallet.reload, :ongoing_usage_balance_cents).from(200).to(1100)
        .and change(wallet, :credits_ongoing_usage_balance).from(2.0).to(11.0)
        .and change(wallet, :ongoing_balance_cents).from(800).to(-100)
        .and change(wallet, :credits_ongoing_balance).from(8.0).to(-1.0)
    end

    it 'returns the wallet' do
      expect(refresh_service.call.wallet).to eq(wallet)
    end
  end
end

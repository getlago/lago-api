# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallets::RefreshCreditsService, type: :service do
  subject(:refresh_service) { described_class.new(wallet:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:wallet) { create(:wallet, customer:, balance: 10.0, credits_balance: 10.0) }

  let(:plan) { create(:plan, organization:) }
  let(:charge) { create(:standard_charge, plan:) }
  let(:subscription) { create(:active_subscription, customer:, plan:) }

  let(:event) do
    create(
      :event,
      external_subscription_id: subscription.external_id,
      code: charge.billable_metric.code,
    )
  end

  before do
    charge
    subscription
    event
  end

  describe 'call' do
    it 'updates amount on the wallet' do
      expect { refresh_service.call }.to change { wallet.reload.consumed_amount_cents }.from(0).to(1000)
        .and change(wallet, :balance_cents).from(1000).to(0)
    end

    it 'returns the wallet' do
      expect(refresh_service.call.wallet).to eq(wallet)
    end
  end
end

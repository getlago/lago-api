# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventDestinations::WalletAmountsService do
  subject(:result) { described_class.call(subscription:, active_wallets: customer.wallets.active.to_a, from_datetime:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:) }
  let(:billable_metric_id) { create(:billable_metric, organization:).id }
  let(:from_datetime) { Time.zone.parse("2026-10-01") }
  let(:period) { "2026-10-01T00:00:00Z" }
  let(:wallet) { create(:wallet, customer:, organization:, ongoing_billable_metric_amounts: {subscription.id => {period => {billable_metric_id => 300}}}) }

  before { wallet }

  def bill(wallet:, amounts:, invoice_subscription: subscription, charges_from_datetime: from_datetime, status: :finalized, **invoice_subscription_attributes)
    invoice = create(:invoice, customer:, organization:, status:)
    create(:invoice_subscription, invoice:, subscription: invoice_subscription, charges_from_datetime:, **invoice_subscription_attributes)
    create(:wallet_transaction, wallet:, invoice:, transaction_type: :outbound, billable_metric_amounts: amounts && {invoice_subscription.id => amounts})
  end

  it "returns what each active wallet absorbs now" do
    expect(result.amounts).to eq({billable_metric_id => {wallet.id => 300}})
  end

  context "with usage billed to the wallet in the period" do
    before { bill(wallet:, amounts: {billable_metric_id => 200}) }

    it "adds it to what the wallet absorbs now" do
      expect(result.amounts).to eq({billable_metric_id => {wallet.id => 500}})
    end
  end

  context "with a terminated wallet that paid in the period" do
    let(:terminated_wallet) do
      create(:wallet, :terminated, customer:, organization:, ongoing_billable_metric_amounts: {subscription.id => {period => {billable_metric_id => 999}}})
    end

    before { bill(wallet: terminated_wallet, amounts: {billable_metric_id => 100}) }

    it "keeps what it paid, but not its stale ongoing amounts" do
      expect(result.amounts).to eq({billable_metric_id => {wallet.id => 300, terminated_wallet.id => 100}})
    end
  end

  context "with ongoing usage of another subscription on the wallet" do
    let(:other_subscription) { create(:subscription, customer:, organization:) }
    let(:wallet) do
      create(:wallet, customer:, organization:, ongoing_billable_metric_amounts: {
        subscription.id => {period => {billable_metric_id => 300}},
        other_subscription.id => {period => {billable_metric_id => 999}}
      })
    end

    it "reads only this subscription's share" do
      expect(result.amounts).to eq({billable_metric_id => {wallet.id => 300}})
    end
  end

  context "with last period's draft still in the ongoing amounts" do
    let(:wallet) do
      create(:wallet, customer:, organization:, ongoing_billable_metric_amounts: {
        subscription.id => {"2026-09-01T00:00:00Z" => {billable_metric_id => 100}, period => {billable_metric_id => 300}}
      })
    end

    it "leaves it out of the current period" do
      expect(result.amounts).to eq({billable_metric_id => {wallet.id => 300}})
    end

    context "with a window starting before that period, as the lifetime record has" do
      let(:from_datetime) { Time.zone.parse("2026-09-01") }

      it "counts it" do
        expect(result.amounts).to eq({billable_metric_id => {wallet.id => 400}})
      end
    end
  end

  context "with an invoice covering this subscription and another one" do
    let(:other_subscription) { create(:subscription, customer:, organization:) }

    before do
      invoice = create(:invoice, customer:, organization:, status: :finalized)
      create(:invoice_subscription, invoice:, subscription:, charges_from_datetime: from_datetime)
      create(:invoice_subscription, invoice:, subscription: other_subscription, charges_from_datetime: from_datetime)
      create(:wallet_transaction, wallet:, invoice:, transaction_type: :outbound, billable_metric_amounts: {
        subscription.id => {billable_metric_id => 200},
        other_subscription.id => {billable_metric_id => 700}
      })
    end

    it "counts only what the wallet paid for this subscription" do
      expect(result.amounts).to eq({billable_metric_id => {wallet.id => 500}})
    end
  end

  context "with a voided invoice" do
    before { bill(wallet:, amounts: {billable_metric_id => 200}, status: :voided) }

    it "ignores it, since voiding gives the credits back" do
      expect(result.amounts).to eq({billable_metric_id => {wallet.id => 300}})
    end
  end

  context "with a pay-in-advance invoice issued in the period" do
    before do
      bill(wallet:, amounts: {billable_metric_id => 200}, charges_from_datetime: from_datetime - 1.month,
        invoicing_reason: :in_advance_charge, timestamp: from_datetime + 2.days)
    end

    it "counts it, although it records the previous period as its charges window" do
      expect(result.amounts).to eq({billable_metric_id => {wallet.id => 500}})
    end
  end

  context "with a pay-in-advance invoice issued before the period" do
    before do
      bill(wallet:, amounts: {billable_metric_id => 200}, charges_from_datetime: from_datetime - 1.month,
        invoicing_reason: :in_advance_charge, timestamp: from_datetime - 1.day)
    end

    it "ignores it" do
      expect(result.amounts).to eq({billable_metric_id => {wallet.id => 300}})
    end
  end

  context "with an invoice for an earlier period" do
    before { bill(wallet:, amounts: {billable_metric_id => 200}, charges_from_datetime: from_datetime - 1.month) }

    it "ignores it" do
      expect(result.amounts).to eq({billable_metric_id => {wallet.id => 300}})
    end
  end

  context "with an invoice of another subscription" do
    before { bill(wallet:, amounts: {billable_metric_id => 200}, invoice_subscription: create(:subscription, customer:, organization:)) }

    it "ignores it" do
      expect(result.amounts).to eq({billable_metric_id => {wallet.id => 300}})
    end
  end

  context "with a transaction created before amounts were recorded" do
    before { bill(wallet:, amounts: nil) }

    it "ignores it" do
      expect(result.amounts).to eq({billable_metric_id => {wallet.id => 300}})
    end
  end
end

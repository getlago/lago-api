# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventDestinations::WalletAmountsService do
  subject(:result) { described_class.call(subscription:, active_wallets: customer.wallets.active.to_a, from_datetime:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:) }
  let(:billable_metric_id) { create(:billable_metric, organization:).id }
  let(:from_datetime) { Time.zone.parse("2026-10-01") }
  let(:wallet) { create(:wallet, customer:, organization:, ongoing_billable_metric_amounts: {billable_metric_id => 300}) }

  before { wallet }

  def bill(wallet:, amounts:, invoice_subscription: subscription, charges_from_datetime: from_datetime, status: :finalized)
    invoice = create(:invoice, customer:, organization:, status:)
    create(:invoice_subscription, invoice:, subscription: invoice_subscription, charges_from_datetime:)
    create(:wallet_transaction, wallet:, invoice:, transaction_type: :outbound, billable_metric_amounts: amounts)
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
      create(:wallet, :terminated, customer:, organization:, ongoing_billable_metric_amounts: {billable_metric_id => 999})
    end

    before { bill(wallet: terminated_wallet, amounts: {billable_metric_id => 100}) }

    it "keeps what it paid, but not its stale ongoing amounts" do
      expect(result.amounts).to eq({billable_metric_id => {wallet.id => 300, terminated_wallet.id => 100}})
    end
  end

  context "with a voided invoice" do
    before { bill(wallet:, amounts: {billable_metric_id => 200}, status: :voided) }

    it "ignores it, since voiding gives the credits back" do
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

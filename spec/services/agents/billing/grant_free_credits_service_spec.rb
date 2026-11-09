# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::Billing::GrantFreeCreditsService, :premium do
  subject(:result) { described_class.call(storefront:, registration:) }

  let(:organization) { create(:organization, premium_integrations: %w[agent_storefront]) }
  let(:storefront) { create(:agent_storefront_integration, organization:) }
  let(:registration) { create(:agent_registration, storefront:) }
  let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "USD") }
  let(:claim) { create(:agent_claim, :verified, registration:) }
  let(:free_credits_cents) { 1000 }
  let(:wallet) { registration.wallet }

  before do
    storefront.update!(plans: [{plan_code: plan.code, free_credits_cents:}.compact])
    Agents::Billing::EnrollService.call!(storefront:, registration:, plan_code: plan.code)
    claim
  end

  it "grants the plan's free credits to the wallet, settled at once" do
    expect { result }.to have_enqueued_job(SendWebhookJob).with("wallet_transaction.created", WalletTransaction)

    expect(result).to be_success
    expect(result.replayed).to be(false)
    expect(result.grant).to have_attributes(organization:, registration:, email_hash: claim.email_hash, amount_cents: 1000)
    expect(result.grant.wallet_transaction).to have_attributes(
      wallet:, transaction_type: "inbound", transaction_status: "granted", status: "settled", source: "manual", credit_amount: 10, amount: 10
    )
    expect(wallet.reload.balance_cents).to eq(1000)
  end

  it "returns the same grant when the agent asks again, whatever the plan offers by then" do
    first = described_class.call(storefront:, registration:)
    storefront.update!(plans: [{plan_code: plan.code}])

    expect(result).to be_success
    expect(result.replayed).to be(true)
    expect(result.grant).to eq(first.grant)
    expect(wallet.wallet_transactions.count).to eq(1)
  end

  context "when another agent of the same owner was served first" do
    let(:other) { create(:agent_registration, storefront:) }

    before do
      Agents::Billing::EnrollService.call!(storefront:, registration: other, plan_code: plan.code)
      create(:agent_claim, :verified, registration: other)
      described_class.call(storefront:, registration: other)
    end

    it "refuses and writes no credit" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(base: ["free_credits_already_granted"])
      expect(wallet.reload.balance_cents).to eq(0)
      expect(wallet.wallet_transactions).to be_empty
      expect(Agents::FreeCreditGrant.count).to eq(1)
    end
  end

  context "when the same owner was served on another storefront of the organization" do
    let(:other_storefront) { create(:agent_storefront_integration, organization:, code: "other_storefront", stripe_provider: create(:stripe_provider, organization:, code: "stripe_other")) }
    let(:other) { create(:agent_registration, storefront: other_storefront) }

    before do
      other_storefront.update!(plans: [{plan_code: plan.code, free_credits_cents: 500}])
      Agents::Billing::EnrollService.call!(storefront: other_storefront, registration: other, plan_code: plan.code)
      create(:agent_claim, :verified, registration: other)
      described_class.call(storefront: other_storefront, registration: other)
    end

    it "grants again: each storefront makes its own offer" do
      expect(result).to be_success
      expect(result.grant.amount_cents).to eq(1000)
      expect(Agents::FreeCreditGrant.count).to eq(2)
    end
  end

  context "when the agent is not claimed yet" do
    let(:claim) { create(:agent_claim, :started, registration:) }

    it "returns claim_required" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(base: ["claim_required"])
      expect(Agents::FreeCreditGrant.count).to eq(0)
    end
  end

  context "when the registration is not enrolled" do
    subject(:result) { described_class.call(storefront:, registration: create(:agent_registration, storefront:)) }

    it "returns enrollment_required" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(base: ["enrollment_required"])
    end
  end

  context "when the plan offers no free credits" do
    let(:free_credits_cents) { nil }

    it "returns free_credits_not_offered" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(base: ["free_credits_not_offered"])
      expect(Agents::FreeCreditGrant.count).to eq(0)
    end
  end

  context "when the plan offers zero" do
    let(:free_credits_cents) { 0 }

    it "returns free_credits_not_offered" do
      expect(result.error.messages).to eq(base: ["free_credits_not_offered"])
    end
  end

  context "when the wallet is written while the credits are granted", transaction: false do
    it "holds the wallet until the grant is committed, so the balance increase never has to retry" do
      wallet_id = wallet.id
      writer = nil
      writer_waited = nil
      allow(WalletTransactions::CreateFromParamsService).to receive(:call).and_wrap_original do |original, **args|
        # An ongoing-balance refresh, say, writing the wallet while the grant is in progress.
        writer = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            Wallet.find(wallet_id).update!(name: "refreshed")
          rescue ActiveRecord::StaleObjectError
            # The grant committed first and bumped the version: the writer reloads and writes again, as a refresh job does.
            retry
          end
        end
        sleep 0.5
        writer_waited = writer.alive?

        original.call(**args)
      end

      expect(result).to be_success
      writer.join

      expect(writer_waited).to be(true)
      expect(wallet.reload).to have_attributes(name: "refreshed", balance_cents: 1000)
      expect(wallet.wallet_transactions.count).to eq(1)
    end
  end

  context "when the same agent asks twice at once", transaction: false do
    it "grants once and answers the second request with the same grant" do
      # The first request pauses before creating the transaction, so the second runs while the first
      # has not committed yet.
      first_call = Queue.new
      first_call << true
      paused = Queue.new
      resume = Queue.new
      allow(WalletTransactions::CreateFromParamsService).to receive(:call).and_wrap_original do |original, **args|
        if first_call.pop(timeout: 0)
          paused << true
          resume.pop
        end

        original.call(**args)
      end

      ask = lambda do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call(storefront: storefront.class.find(storefront.id), registration: registration.class.find(registration.id))
          end
        end
      end

      first = ask.call
      paused.pop
      second = ask.call
      sleep 0.5
      resume << true

      results = [first.value, second.value]

      expect(results).to all(be_success)
      expect(results.map(&:replayed)).to eq([false, true])
      expect(registration.wallet.wallet_transactions.count).to eq(1)
      expect(Agents::FreeCreditGrant.count).to eq(1)
    end
  end
end

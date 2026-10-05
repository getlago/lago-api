# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::AdvanceChargesToDatetimeFilterResolver do
  subject(:relation) do
    described_class.new(billing_contexts: [billing_context], billing_at: Time.current, customer:).call
  end

  let(:customer) { nil }

  context "when the context is a contract" do
    let(:customer) { build_stubbed(:customer) }
    let(:billing_context) { Billing::Context.from(contract: build_stubbed(:contract, status: :active)) }

    it "applies the charge boundary without looking for a next subscription" do
      expect(relation.to_sql).to include("charges_to_datetime")
    end
  end

  context "when an active subscription has a next subscription" do
    let(:subscription) { build_stubbed(:subscription, status: :active) }
    let(:billing_context) { Billing::Context.from(subscription:) }

    before do
      allow(subscription).to receive(:next_subscription).and_return(build_stubbed(:subscription))
    end

    it "does not apply the regular periodic charge boundary" do
      expect(relation.to_sql).not_to include("charges_to_datetime")
    end

    it "scopes eligible fees to the subscription and succeeded payment" do
      expect(relation.to_sql).to include("subscription_id", "invoice_id", "payment_status", "succeeded_at")
    end
  end
end

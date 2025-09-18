# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdjustedFees::EstimateService do
  subject(:estimate_service) { described_class.new(invoice:, params:) }

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }

  let(:invoice) do
    create(
      :invoice,
      :voided,
      :with_subscriptions,
      organization:,
      customer:,
      subscriptions: [subscription],
      currency: "EUR"
    )
  end

  let(:subscription) do
    create(
      :subscription,
      plan:,
      subscription_at: started_at,
      started_at:,
      created_at: started_at
    )
  end

  let(:timestamp) { Time.zone.now - 1.year }
  let(:started_at) { Time.zone.now - 2.years }
  let(:plan) { create(:plan, organization:, interval: "monthly") }
  let(:fee_subscription) do
    create(
      :fee,
      invoice: invoice,
      subscription:,
      fee_type: :subscription,
      precise_unit_amount: 20.00,
      units: 10
    )
  end

  describe "#call" do
    before do
      fee_subscription
    end

    context "when adjusting invoice display name" do
      let(:params) do
        {
          fee_id: fee_subscription.id,
          subscription_id: fee_subscription.subscription_id,
          invoice_display_name: "new-dis-name"
        }
      end

      it "returns adjusted fee in the result" do
        result = estimate_service.call
        expect(result.fee).to be_a(Fee)
        expect(result.fee.invoice_display_name).to eq "new-dis-name"
        expect(result.fee.units).to eq 10
        expect(result.fee.precise_unit_amount).to eq 20.00
      end
    end

    context "when adjusting units" do
      let(:params) do
        {
          fee_id: fee_subscription.id,
          subscription_id: fee_subscription.subscription_id,
          units: 5,
          invoice_display_name: "new-dis-name"
        }
      end

      it "returns adjusted fee in the result" do
        result = estimate_service.call
        expect(result.fee).to be_a(Fee)
        expect(result.fee.invoice_display_name).to eq "new-dis-name"
        expect(result.fee.units).to eq 5
      end
    end

    context "when adjusting units and unit amount" do
      let(:params) do
        {
          fee_id: fee_subscription.id,
          subscription_id: fee_subscription.subscription_id,
          units: 15,
          unit_precise_amount: 12.002,
          invoice_display_name: "new-dis-name"
        }
      end

      it "returns adjusted fee in the result" do
        result = estimate_service.call
        expect(result.fee).to be_a(Fee)
        expect(result.fee).to have_attributes(
          units: 15.0,
          unit_amount_cents: 1200,
          precise_unit_amount: 12.002,
          invoice_display_name: "new-dis-name"
        )
      end
    end
  end
end

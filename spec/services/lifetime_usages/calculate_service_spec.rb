# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LifetimeUsages::CalculateService, type: :service do
  subject(:service) { described_class.new(lifetime_usage: lifetime_usage) }

  let(:lifetime_usage) { create(:lifetime_usage, subscription:, recalculate_current_usage:, recalculate_invoiced_usage:) }
  let(:recalculate_current_usage) { false }
  let(:recalculate_invoiced_usage) { false }
  let(:subscription) { create(:subscription, customer_id: customer.id) }
  let(:organization) { subscription.organization }
  let(:customer) { create(:customer) }

  let(:invoice_subscription) { create(:invoice_subscription, invoice: invoice, subscription: subscription) }
  let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }
  let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:, properties: {amount: '10'}) }
  let(:timestamp) { Time.current }
  let(:fees) do
    create_list(
      :charge_fee,
      2,
      invoice:,
      charge:,
      amount_cents: 100,
      precise_coupons_amount_cents: 50
    )
  end

  let(:events) do
    create_list(
      :event,
      2,
      organization:,
      subscription:,
      customer:,
      code: billable_metric.code,
      timestamp:
    )
  end

  describe '#recalculate_invoiced_usage' do
    let(:recalculate_invoiced_usage) { true }

    context "without previous invoices" do
      it "calculates the invoiced_usage as zero" do
        result = service.call
        expect(result.lifetime_usage.invoiced_usage_amount_cents).to be_zero
      end

      it "updates the invoiced_usage_amount_refreshed_at" do
        expect { service.call }.to change(lifetime_usage, :invoiced_usage_amount_refreshed_at)
      end

      it "does not change current_usage_amount_refreshed_at" do
        expect { service.call }.not_to change(lifetime_usage, :current_usage_amount_refreshed_at)
      end
    end

    context "with draft invoice" do
      let(:invoice) { create(:invoice, :draft) }

      before do
        invoice
        invoice_subscription
        fees
      end

      it "calculates the invoiced_usage as zero" do
        result = service.call
        expect(result.lifetime_usage.invoiced_usage_amount_cents).to be_zero
      end
    end

    context "with finalized invoice" do
      let(:invoice) { create(:invoice, :finalized) }

      before do
        invoice
        invoice_subscription
        fees
      end

      it "calculates the invoiced_usage_amount_cents correctly" do
        result = service.call
        expect(result.lifetime_usage.invoiced_usage_amount_cents).to eq(200)
        expect(lifetime_usage.reload.invoiced_usage_amount_cents).to eq(200)
        expect(lifetime_usage.recalculate_invoiced_usage).to be false
      end
    end
  end

  describe '#recalculate_current_usage' do
    let(:recalculate_current_usage) { true }

    context 'without usage' do
      it 'calculates the current_usage as zero' do
        result = service.call
        expect(result.lifetime_usage.current_usage_amount_cents).to be_zero
      end
    end

    it "updates the current_usage_amount_refreshed_at" do
      expect { service.call }.to change(lifetime_usage, :current_usage_amount_refreshed_at)
    end

    it "does not change invoiced_usage_amount_refreshed_at" do
      expect { service.call }.not_to change(lifetime_usage, :invoiced_usage_amount_refreshed_at)
    end

    context 'with usage' do
      before do
        events
        charge
        Rails.cache.clear
      end

      it 'calculates the current_usage_amount_cents correctly' do
        result = service.call
        expect(result.lifetime_usage.current_usage_amount_cents).to eq(2000)
        expect(lifetime_usage.reload.current_usage_amount_cents).to eq(2000)
        expect(lifetime_usage.recalculate_current_usage).to be false
      end
    end
  end
end

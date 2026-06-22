# frozen_string_literal: true

require "rails_helper"

describe Subscriptions::EnsureBilledForPeriodService do
  subject(:result) { described_class.call(subscription:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, pay_in_advance: true) }
  let(:subscription) do
    create(:subscription, organization:, customer:, plan:, status: :active,
      started_at: 1.month.ago, subscription_at: 1.month.ago)
  end
  let(:timestamp) { Time.current }

  def bill_period_invoice(status:)
    create(:invoice_subscription,
      subscription:,
      invoice: create(:invoice, customer:, organization:, status:),
      recurring: true, from_datetime: 1.day.ago, to_datetime: 1.month.from_now)
  end

  context "when the plan is pay in advance" do
    context "when billing produces a usable invoice for the period" do
      before { allow(BillSubscriptionJob).to receive(:perform_now) { bill_period_invoice(status: :finalized) } }

      it "bills the subscription synchronously for the period" do
        result

        expect(BillSubscriptionJob).to have_received(:perform_now)
          .with([subscription], timestamp.to_i, invoicing_reason: :subscription_periodic)
      end

      it "returns success" do
        expect(result).to be_success
      end
    end

    context "when billing leaves no usable invoice for the period" do
      before { allow(BillSubscriptionJob).to receive(:perform_now) }

      it "raises NotBilledError" do
        expect { result }.to raise_error(described_class::NotBilledError)
      end
    end

    context "when the period invoice is still generating" do
      before { allow(BillSubscriptionJob).to receive(:perform_now) { bill_period_invoice(status: :generating) } }

      it "raises NotBilledError" do
        expect { result }.to raise_error(described_class::NotBilledError)
      end
    end
  end

  context "when the plan is pay in arrears" do
    let(:plan) { create(:plan, organization:, pay_in_advance: false) }

    before { allow(BillSubscriptionJob).to receive(:perform_now) }

    it "does not bill the subscription" do
      result

      expect(BillSubscriptionJob).not_to have_received(:perform_now)
    end

    it "returns success" do
      expect(result).to be_success
    end
  end

  context "when the subscription is no longer active" do
    let(:subscription) do
      create(:subscription, organization:, customer:, plan:, status: :terminated,
        started_at: 1.month.ago, subscription_at: 1.month.ago, terminated_at: 1.day.ago)
    end

    before { allow(BillSubscriptionJob).to receive(:perform_now) }

    it "does not bill the subscription" do
      result

      expect(BillSubscriptionJob).not_to have_received(:perform_now)
    end

    it "returns success" do
      expect(result).to be_success
    end
  end
end

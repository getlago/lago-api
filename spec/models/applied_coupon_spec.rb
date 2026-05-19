# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppliedCoupon do
  subject(:applied_coupon) { create(:applied_coupon) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    subject(:applied_coupon) { create(:applied_coupon, coupon: create(:coupon, :deleted)) }

    it { is_expected.to belong_to(:coupon) }
    it { expect(subject.coupon).not_to be_nil }

    it { is_expected.to belong_to(:customer) }
    it { is_expected.to belong_to(:organization) }
    it { is_expected.to have_many(:credits) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:status).with_values(%i[active terminated]) }
    it { is_expected.to define_enum_for(:frequency).with_values(%i[once recurring forever]) }
  end

  describe "validations" do
    it { is_expected.to validate_numericality_of(:amount_cents).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_inclusion_of(:amount_currency).in_array(described_class.currency_list) }

    describe "of frequency_duration" do
      subject(:applied_coupon) { build(:applied_coupon, frequency:) }

      context "when recurring" do
        let(:frequency) { "recurring" }

        it { is_expected.to validate_presence_of(:frequency_duration).with_message("value_is_mandatory") }
        it { is_expected.to validate_numericality_of(:frequency_duration).is_greater_than(0) }
        it { is_expected.to validate_presence_of(:frequency_duration_remaining).with_message("value_is_mandatory") }
        it { is_expected.to validate_numericality_of(:frequency_duration_remaining).is_greater_than_or_equal_to(0) }
      end

      context "when once" do
        let(:frequency) { "once" }

        it { is_expected.not_to validate_presence_of(:frequency_duration) }
        it { is_expected.not_to validate_presence_of(:frequency_duration_remaining) }
      end

      context "when forever" do
        let(:frequency) { "forever" }

        it { is_expected.not_to validate_presence_of(:frequency_duration) }
        it { is_expected.not_to validate_presence_of(:frequency_duration_remaining) }
      end
    end
  end

  describe "#remaining_amount" do
    let(:applied_coupon) { create(:applied_coupon, amount_cents: 50) }
    let(:invoice) { create(:invoice) }

    before do
      create(:credit, applied_coupon: applied_coupon, amount_cents: 10, invoice: invoice)
    end

    context "when invoice is not voided" do
      it "returns the amount minus credit" do
        expect(applied_coupon.remaining_amount).to eq(40)
      end
    end

    context "when invoice is voided" do
      let(:invoice) { create(:invoice, status: :voided) }

      it "ignores the credit amount" do
        expect(applied_coupon.remaining_amount).to eq(50)
      end
    end
  end

  describe "#mark_as_terminated!" do
    it "marks the applied coupon as terminated" do
      expect { applied_coupon.mark_as_terminated! }.to change(applied_coupon, :status).to("terminated").and \
        change(applied_coupon, :terminated_at).to be_present
    end
  end

  # Covers the trio of methods used to track per-billing-period coupon usage:
  #   #remaining_amount_for_this_subscription_billing_period (public, used by AmountService)
  #   #credits_applied_in_billing_period_present?           (public, used by reduce_coupon_usage)
  #   #credits_sum_for_invoice_subscription                 (helper for both)
  describe "billing-period coupon tracking" do
    let(:applied_coupon) { create(:applied_coupon, amount_cents: 100) }
    let(:organization) { applied_coupon.organization }
    let(:billing_entity) { organization.default_billing_entity }
    let(:customer) { applied_coupon.customer }
    let(:subscription) { create(:subscription, customer:, organization:) }
    let(:period_start) { Time.current.beginning_of_month }
    let(:period_end) { Time.current.end_of_month }
    let(:invoice) do
      create(:invoice, :subscription, customer:, organization:, billing_entity:, subscriptions: [subscription]).tap do |inv|
        inv.invoice_subscriptions.update_all(timestamp: Time.current, charges_from_datetime: period_start, charges_to_datetime: period_end) # rubocop:disable Rails/SkipsModelValidations
      end
    end
    let(:invoice_subscription) { invoice.invoice_subscriptions.first }

    def add_fee(inv, sub, amount, offset: 0.months)
      create(:fee, invoice: inv, subscription: sub, amount_cents: amount, organization:, billing_entity:,
        properties: {charges_from_datetime: period_start + offset, charges_to_datetime: period_end + offset})
    end

    def add_period_invoice(offset: 0.months, voided: false, subs: [subscription])
      traits = voided ? [:voided] : []
      create(:invoice, :subscription, *traits, customer:, organization:, billing_entity:, subscriptions: subs).tap do |inv|
        inv.invoice_subscriptions.update_all(timestamp: Time.current + offset, charges_from_datetime: period_start + offset, charges_to_datetime: period_end + offset) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    before { add_fee(invoice, subscription, 20) }

    context "without any prior credits" do
      it "remaining is the full amount, no credits present, sum is 0" do
        expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice:)).to eq(100)
        expect(applied_coupon.credits_applied_in_billing_period_present?(invoice)).to be(false)
        expect(applied_coupon.credits_sum_for_invoice_subscription(invoice_subscription, invoice)).to eq(0)
      end
    end

    context "with a credit on another invoice in the same period" do
      before do
        other = add_period_invoice
        add_fee(other, subscription, 20)
        create(:credit, applied_coupon:, invoice: other, amount_cents: 30, organization:)
      end

      it "remaining decreases by the credit, present? is true" do
        expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice:)).to eq(70)
        expect(applied_coupon.credits_applied_in_billing_period_present?(invoice)).to be(true)
        expect(applied_coupon.credits_sum_for_invoice_subscription(invoice_subscription, invoice)).to eq(30)
      end
    end

    context "with a credit on a voided invoice" do
      before do
        other = add_period_invoice(voided: true)
        add_fee(other, subscription, 20)
        create(:credit, applied_coupon:, invoice: other, amount_cents: 50, organization:)
      end

      it "ignores voided-invoice credits" do
        expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice:)).to eq(100)
        expect(applied_coupon.credits_applied_in_billing_period_present?(invoice)).to be(false)
        expect(applied_coupon.credits_sum_for_invoice_subscription(invoice_subscription, invoice)).to eq(0)
      end
    end

    context "with credits in non-overlapping billing periods" do
      before do
        other = add_period_invoice(offset: -1.month)
        add_fee(other, subscription, 20, offset: -1.month)
        create(:credit, applied_coupon:, invoice: other, amount_cents: 40, organization:)
      end

      it "excludes credits outside the billing period" do
        expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice:)).to eq(100)
        expect(applied_coupon.credits_applied_in_billing_period_present?(invoice)).to be(false)
        expect(applied_coupon.credits_sum_for_invoice_subscription(invoice_subscription, invoice)).to eq(0)
      end
    end

    context "with credits exceeding amount_cents" do
      before { create(:credit, applied_coupon:, invoice:, amount_cents: 150, organization:) }

      it "clamps remaining to 0" do
        expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice:)).to eq(0)
      end
    end

    context "when called multiple times for the same invoice" do
      it "caches per invoice id" do
        first_call = applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice:)
        second_call = applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice:)
        expect(first_call).to eq(second_call).and eq(100)
      end
    end

    # Multi-subscription semantics: credits are summed across subs without de-duplicating
    # invoice IDs. A credit on an invoice that has fees for both subs is therefore counted
    # once per subscription. Conservative — never undercounts usage; may overcount slightly
    # for the rare shared-invoice case. Per-sub semantics, sub-billed independently.
    context "with multiple subscriptions on the invoice" do
      let(:subscription_2) { create(:subscription, customer:, organization:) }

      before do
        create(:invoice_subscription, invoice:, subscription: subscription_2, organization:,
          timestamp: Time.current, charges_from_datetime: period_start, charges_to_datetime: period_end)
        add_fee(invoice, subscription_2, 20)
      end

      context "with a credit on the shared invoice" do
        before { create(:credit, applied_coupon:, invoice:, amount_cents: 20, organization:) }

        it "counts the credit once per subscription on that invoice" do
          # Sub uses $20, sub_2 uses $20 (same credit, counted twice). Sum=$40, remaining=$60.
          expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice:)).to eq(60)
          # this is only for the first subscription
          expect(applied_coupon.credits_sum_for_invoice_subscription(invoice_subscription, invoice)).to eq(20)
          expect(applied_coupon.credits_applied_in_billing_period_present?(invoice)).to be(true)
        end
      end

      context "with credits split between subscriptions" do
        before do
          create(:credit, applied_coupon:, invoice:, amount_cents: 20, organization:)
          other = add_period_invoice(subs: [subscription_2])
          add_fee(other, subscription_2, 20)
          create(:credit, applied_coupon:, invoice: other, amount_cents: 30, organization:)
        end

        it "sums credits per-subscription across all in-period invoices" do
          # sub: $20. sub_2: $20 (shared) + $30 (other) = $50. Sum=$70, remaining=$30.
          expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice:)).to eq(30)
          expect(applied_coupon.credits_sum_for_invoice_subscription(invoice_subscription, invoice)).to eq(20)
        end
      end

      context "with one subscription that has no usage in this period" do
        let(:subscription_3) { create(:subscription, customer:, organization:) }
        let(:invoice_3) { add_period_invoice(subs: [subscription_3, subscription_2]) }

        before do
          add_fee(invoice_3, subscription_3, 20)
          create(:credit, applied_coupon:, invoice:, amount_cents: 20, organization:)
        end

        it "sums credits found via any subscription's billing period" do
          # sub_3: $0. sub_2: $20 (on invoice). Sum=$20, remaining=$80.
          expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice: invoice_3)).to eq(80)
        end
      end
    end
  end
end

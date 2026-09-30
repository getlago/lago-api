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

    context "when invoice is closed" do
      let(:invoice) { create(:invoice, status: :closed) }

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

  describe "billing period usage" do
    let(:applied_coupon) { create(:applied_coupon, amount_cents: 100) }
    let(:organization) { applied_coupon.organization }
    let(:billing_entity) { organization.default_billing_entity }
    let(:customer) { applied_coupon.customer }
    let(:subscription) { create(:subscription, customer:, organization:) }
    let(:period_start) { Time.current.beginning_of_month }
    let(:period_end) { Time.current.end_of_month }
    let(:charges_boundaries) { {charges_from_datetime: period_start, charges_to_datetime: period_end} }
    let(:fixed_charges_boundaries) { {fixed_charges_from_datetime: period_start, fixed_charges_to_datetime: period_end} }
    let(:invoice) { add_period_invoice }

    def add_fee(inv, sub, properties: charges_boundaries)
      create(:fee, invoice: inv, subscription: sub, amount_cents: 20, organization:, billing_entity:, properties:)
    end

    def add_period_invoice(offset: 0.months, voided: false, subs: [subscription])
      traits = voided ? [:voided] : []
      create(:invoice, :subscription, *traits, customer:, organization:, billing_entity:, subscriptions: subs).tap do |inv|
        inv.invoice_subscriptions.update_all(timestamp: Time.current + offset, charges_from_datetime: period_start + offset, charges_to_datetime: period_end + offset) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    def add_credit(inv, amount_cents)
      create(:credit, applied_coupon:, invoice: inv, amount_cents:, organization:)
    end

    before { add_fee(invoice, subscription) }

    context "without any prior credits" do
      it "returns the full amount" do
        expect(applied_coupon.remaining_amount_in_billing_period(invoice)).to eq(100)
        expect(applied_coupon.used_in_billing_period?(invoice)).to be(false)
      end
    end

    context "with a credit on another invoice in the same period" do
      before { add_credit(add_period_invoice.tap { |other| add_fee(other, subscription) }, 30) }

      it "deducts the credit" do
        expect(applied_coupon.remaining_amount_in_billing_period(invoice)).to eq(70)
        expect(applied_coupon.used_in_billing_period?(invoice)).to be(true)
      end
    end

    context "with a credit on a voided invoice" do
      before { add_credit(add_period_invoice(voided: true).tap { |other| add_fee(other, subscription) }, 50) }

      it "ignores the credit" do
        expect(applied_coupon.remaining_amount_in_billing_period(invoice)).to eq(100)
        expect(applied_coupon.used_in_billing_period?(invoice)).to be(false)
      end
    end

    context "with a credit in the previous billing period" do
      before do
        other = add_period_invoice(offset: -1.month)
        add_fee(other, subscription, properties: {charges_from_datetime: period_start - 1.month, charges_to_datetime: period_end - 1.month})
        add_credit(other, 40)
      end

      it "ignores the credit" do
        expect(applied_coupon.remaining_amount_in_billing_period(invoice)).to eq(100)
        expect(applied_coupon.used_in_billing_period?(invoice)).to be(false)
      end
    end

    context "with credits exceeding the coupon amount" do
      before { add_credit(invoice, 150) }

      it "returns zero" do
        expect(applied_coupon.remaining_amount_in_billing_period(invoice)).to eq(0)
      end
    end

    context "with a fee without charges boundaries on the invoice" do
      before do
        add_fee(invoice, subscription, properties: {from_datetime: period_start - 1.month, to_datetime: period_end - 1.month})
        add_credit(add_period_invoice.tap { |other| add_fee(other, subscription) }, 30)
      end

      it "uses the boundaries of the fees that have them" do
        expect(applied_coupon.remaining_amount_in_billing_period(invoice)).to eq(70)
      end
    end

    context "when the invoice only has a pay-in-advance fixed charge fee" do
      let(:fixed_charge_invoice) { add_period_invoice.tap { |inv| add_fee(inv, subscription, properties: fixed_charges_boundaries) } }

      before { add_credit(invoice, 30) }

      it "uses the fixed charges boundaries" do
        expect(applied_coupon.remaining_amount_in_billing_period(fixed_charge_invoice)).to eq(70)
      end
    end

    context "with a credit on a pay-in-advance fixed charge invoice in the same period" do
      before { add_credit(add_period_invoice.tap { |other| add_fee(other, subscription, properties: fixed_charges_boundaries) }, 30) }

      it "deducts the credit" do
        expect(applied_coupon.remaining_amount_in_billing_period(invoice)).to eq(70)
      end
    end

    context "with multiple subscriptions on the invoice" do
      let(:subscription_2) { create(:subscription, customer:, organization:) }

      before do
        create(:invoice_subscription, invoice:, subscription: subscription_2, organization:,
          timestamp: Time.current, charges_from_datetime: period_start, charges_to_datetime: period_end)
        add_fee(invoice, subscription_2)
      end

      context "with a credit on the shared invoice" do
        before { add_credit(invoice, 20) }

        it "counts the credit once per subscription" do
          expect(applied_coupon.remaining_amount_in_billing_period(invoice)).to eq(60)
          expect(applied_coupon.used_in_billing_period?(invoice)).to be(true)
        end
      end

      context "with credits split between subscriptions" do
        before do
          add_credit(invoice, 20)
          add_credit(add_period_invoice(subs: [subscription_2]).tap { |other| add_fee(other, subscription_2) }, 30)
        end

        it "sums the credits of every subscription billing period" do
          expect(applied_coupon.remaining_amount_in_billing_period(invoice)).to eq(30)
        end
      end

      context "with one subscription that has no usage in this period" do
        let(:subscription_3) { create(:subscription, customer:, organization:) }
        let(:invoice_3) { add_period_invoice(subs: [subscription_3, subscription_2]) }

        before do
          add_fee(invoice_3, subscription_3)
          add_credit(invoice, 20)
        end

        it "sums the credits found through the other subscription" do
          expect(applied_coupon.remaining_amount_in_billing_period(invoice_3)).to eq(80)
        end
      end
    end
  end
end

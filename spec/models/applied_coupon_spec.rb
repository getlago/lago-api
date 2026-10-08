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
    let(:customer) { applied_coupon.customer }
    let(:subscription) { create(:subscription, customer:, organization:) }
    let(:period_start) { Time.current.beginning_of_month }
    let(:previous_period_start) { period_start - 1.month }
    let(:next_period_start) { period_start + 1.month }
    let(:invoice) { create_invoice }

    def create_invoice(voided: false, subs: [subscription])
      traits = voided ? [:voided] : []
      create(:invoice, :subscription, *traits, customer:, organization:, subscriptions: subs)
    end

    def add_charge_fee(inv, sub, from: period_start)
      create(:charge_fee, invoice: inv, subscription: sub, organization:, properties: {
        "from_datetime" => from, "charges_from_datetime" => from, "charges_to_datetime" => from.end_of_month
      })
    end

    def add_subscription_fee(inv, sub, from:, charges_from:)
      create(:fee, invoice: inv, subscription: sub, organization:, properties: {
        "from_datetime" => from, "to_datetime" => from.end_of_month,
        "charges_from_datetime" => charges_from, "charges_to_datetime" => charges_from.end_of_month
      })
    end

    def add_fixed_charge_fee(inv, sub, from: period_start)
      create(:fixed_charge_fee, invoice: inv, subscription: sub, organization:, properties: {
        "charges_from_datetime" => nil, "fixed_charges_from_datetime" => from, "fixed_charges_to_datetime" => from.end_of_month
      })
    end

    def add_credit(inv, amount_cents)
      create(:credit, applied_coupon:, invoice: inv, amount_cents:, organization:)
    end

    before { add_charge_fee(invoice, subscription) }

    context "without any prior credits" do
      it "returns the full amount" do
        expect(applied_coupon.remaining_amount_in_billing_period(invoice)).to eq(100)
        expect(applied_coupon.used_in_billing_period?(invoice)).to be(false)
      end
    end

    context "with a credit on another invoice in the same period" do
      before { add_credit(create_invoice.tap { |other| add_charge_fee(other, subscription) }, 30) }

      it "deducts the credit" do
        expect(applied_coupon.remaining_amount_in_billing_period(invoice)).to eq(70)
        expect(applied_coupon.used_in_billing_period?(invoice)).to be(true)
      end
    end

    context "with a credit on a voided invoice" do
      before { add_credit(create_invoice(voided: true).tap { |other| add_charge_fee(other, subscription) }, 50) }

      it "ignores the credit" do
        expect(applied_coupon.remaining_amount_in_billing_period(invoice)).to eq(100)
        expect(applied_coupon.used_in_billing_period?(invoice)).to be(false)
      end
    end

    context "with a credit in the previous billing period" do
      before { add_credit(create_invoice.tap { |other| add_charge_fee(other, subscription, from: previous_period_start) }, 40) }

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

    context "with a pay-in-advance subscription fee for the next period on the invoice" do
      let(:next_period_invoice) { create_invoice.tap { |other| add_charge_fee(other, subscription, from: next_period_start) } }

      before do
        add_subscription_fee(invoice, subscription, from: next_period_start, charges_from: period_start)
        add_credit(create_invoice.tap { |other| add_charge_fee(other, subscription) }, 30)
        add_credit(next_period_invoice, 20)
      end

      it "uses the latest period of the invoice" do
        expect(applied_coupon.remaining_amount_in_billing_period(invoice)).to eq(80)
      end
    end

    context "with a credit on a subscription fee invoice whose charges boundaries are in the previous period" do
      before do
        add_credit(create_invoice.tap { |other| add_subscription_fee(other, subscription, from: period_start, charges_from: previous_period_start) }, 30)
      end

      it "uses the subscription fee boundaries" do
        expect(applied_coupon.remaining_amount_in_billing_period(invoice)).to eq(70)
      end
    end

    context "with a credit on a pay-in-advance fixed charge invoice in the same period" do
      before { add_credit(create_invoice.tap { |other| add_fixed_charge_fee(other, subscription) }, 30) }

      it "deducts the credit" do
        expect(applied_coupon.remaining_amount_in_billing_period(invoice)).to eq(70)
      end
    end

    context "with an invoice that is not persisted" do
      let(:preview_invoice) { build(:invoice, customer:, organization:, fees: [build(:charge_fee, subscription:, organization:, properties: {"charges_from_datetime" => period_start})]) }

      before { add_credit(invoice, 30) }

      it "reads the billing period from the fees in memory" do
        expect(applied_coupon.remaining_amount_in_billing_period(preview_invoice)).to eq(70)
      end
    end

    context "with multiple subscriptions on the invoice" do
      let(:subscription_2) { create(:subscription, customer:, organization:) }
      let(:invoice) { create_invoice(subs: [subscription, subscription_2]) }

      before { add_charge_fee(invoice, subscription_2) }

      context "with a credit on the shared invoice" do
        before { add_credit(invoice, 20) }

        it "counts the credit once" do
          expect(applied_coupon.remaining_amount_in_billing_period(invoice)).to eq(80)
          expect(applied_coupon.used_in_billing_period?(invoice)).to be(true)
        end
      end

      context "with credits split between subscriptions" do
        before do
          add_credit(invoice, 20)
          add_credit(create_invoice(subs: [subscription_2]).tap { |other| add_charge_fee(other, subscription_2) }, 30)
        end

        it "sums the credits of every subscription billing period" do
          expect(applied_coupon.remaining_amount_in_billing_period(invoice)).to eq(50)
        end
      end
    end
  end
end

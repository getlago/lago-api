# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCard do
  subject(:rate_card) { build(:rate_card) }

  it_behaves_like "paper_trail traceable"

  describe "enums" do
    it do
      expect(rate_card).to define_enum_for(:billing_timing)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(arrears: "arrears", advance: "advance")

      expect(rate_card).to define_enum_for(:regroup_paid_fees)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(none: "none", invoice: "invoice")
        .with_prefix(:regroup_paid_fees)
      expect(rate_card.regroup_paid_fees).to eq("none")
    end
  end

  describe "associations" do
    it do
      expect(rate_card).to belong_to(:organization)
      expect(rate_card).to belong_to(:product)
      expect(rate_card).to belong_to(:product_filter).optional
      expect(rate_card).to have_many(:rates).class_name("RateCardRate")
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:code) }

    describe "filter scoping" do
      it "rejects a filter belonging to another product" do
        organization = create(:organization)
        foreign_filter = create(:product_filter, organization:)
        rate_card = build(:rate_card, organization:, product_filter: foreign_filter)
        rate_card.valid?

        expect(rate_card.errors.where(:product_filter, :does_not_belong_to_product)).to be_present
      end

      it "accepts a filter of the card's own item" do
        filter = create(:product_filter)
        rate_card = build(:rate_card, organization: filter.organization, product: filter.product, product_filter: filter)

        expect(rate_card).to be_valid
      end
    end

    describe "display_on_invoice compatibility" do
      it "rejects hiding fees on an arrears card" do
        hidden = build(:rate_card, billing_timing: "arrears", display_on_invoice: false)
        hidden.valid?
        expect(hidden.errors.where(:display_on_invoice).map(&:type)).to eq([:not_allowed_for_billing_timing])
      end

      it "accepts hiding fees on an advance card" do
        expect(build(:rate_card, billing_timing: "advance", display_on_invoice: false)).to be_valid
      end

      it "accepts a displayed arrears card" do
        expect(build(:rate_card, billing_timing: "arrears", display_on_invoice: true)).to be_valid
      end
    end

    describe "proration compatibility" do
      it "rejects proration on a metered metric" do
        metered = create(:product, billable_metric: create(:billable_metric, recurring: false))
        card = build(:rate_card, organization: metered.organization, product: metered, proration: true)
        card.valid?
        expect(card.errors.where(:proration).map(&:type)).to eq([:requires_recurring_metric])
      end

      it "rejects proration on a weighted_sum metric" do
        metric = create(:billable_metric, aggregation_type: "weighted_sum_agg", recurring: true, field_name: "value", weighted_interval: "seconds")
        product = create(:product, organization: metric.organization, billable_metric: metric)
        card = build(:rate_card, organization: product.organization, product:, proration: true)
        card.valid?
        expect(card.errors.where(:proration).map(&:type)).to eq([:not_allowed_for_aggregation_type])
      end

      it "accepts proration on a recurring metric" do
        metric = create(:billable_metric, aggregation_type: "sum_agg", recurring: true, field_name: "amount")
        product = create(:product, organization: metric.organization, billable_metric: metric)

        expect(build(:rate_card, organization: product.organization, product:, proration: true)).to be_valid
      end

      it "accepts proration on a fixed product" do
        product = create(:product, :fixed, :standalone)

        expect(build(:rate_card, organization: product.organization, product:, proration: true)).to be_valid
      end
    end

    describe "regroup_paid_fees compatibility" do
      it "names the field that actually conflicts" do
        arrears = build(:rate_card, regroup_paid_fees: "invoice", billing_timing: "arrears", display_on_invoice: false)
        arrears.valid?
        expect(arrears.errors.where(:regroup_paid_fees).map(&:type)).to eq([:not_allowed_for_billing_timing])

        displayed = build(:rate_card, regroup_paid_fees: "invoice", billing_timing: "advance", display_on_invoice: true)
        displayed.valid?
        expect(displayed.errors.where(:regroup_paid_fees).map(&:type)).to eq([:not_allowed_with_display_on_invoice])

        both = build(:rate_card, regroup_paid_fees: "invoice", billing_timing: "arrears", display_on_invoice: true)
        both.valid?
        expect(both.errors.where(:regroup_paid_fees).map(&:type))
          .to match_array(%i[not_allowed_for_billing_timing not_allowed_with_display_on_invoice])

        valid = build(:rate_card, regroup_paid_fees: "invoice", billing_timing: "advance", display_on_invoice: false)
        expect(valid).to be_valid
      end
    end

    describe "currency inclusion" do
      it "is valid with an accepted currency" do
        expect(build(:rate_card, currency: "USD")).to be_valid
      end

      it "is invalid with an unknown currency" do
        rate_card = build(:rate_card, currency: "ABC")
        rate_card.valid?
        expect(rate_card.errors.where(:currency, :inclusion)).to be_present
        expect(rate_card.errors.where(:currency, :blank)).to be_empty
      end

      it "reports only the presence error when the currency is missing" do
        rate_card = build(:rate_card, currency: nil)
        rate_card.valid?
        expect(rate_card.errors.where(:currency, :blank)).to be_present
        expect(rate_card.errors.where(:currency, :inclusion)).to be_empty
      end
    end

    describe "code uniqueness per organization" do
      it "rejects a duplicate code within the same organization, even on a different product" do
        existing = create(:rate_card)
        duplicate = build(:rate_card, organization: existing.organization, code: existing.code)
        duplicate.valid?
        expect(duplicate.errors.where(:code, :taken)).to be_present
      end

      it "allows the same code in a different organization" do
        existing = create(:rate_card)
        other = build(:rate_card, code: existing.code)
        other.valid?
        expect(other.errors.where(:code, :taken)).not_to be_present
      end
    end
  end

  describe "#attached_to_plan_or_subscription?" do
    let(:rate_card) { create(:rate_card) }

    it "is false when no plan or subscription references the card" do
      expect(rate_card.attached_to_plan_or_subscription?).to be(false)
    end

    it "is true when a plan references the card" do
      create(:plan_rate_card, organization: rate_card.organization, rate_card:)

      expect(rate_card.attached_to_plan_or_subscription?).to be(true)
    end

    it "is true when a subscription references the card" do
      create(:subscription_rate_card, organization: rate_card.organization, rate_card:)

      expect(rate_card.attached_to_plan_or_subscription?).to be(true)
    end
  end

  describe "#attached_to_subscriptions?" do
    subject(:rate_card) { create(:rate_card) }

    it "is false without any subscription linkage" do
      expect(rate_card.attached_to_subscriptions?).to be(false)
    end

    it "is false when on a plan without subscriptions" do
      create(:plan_rate_card, organization: rate_card.organization, rate_card:)

      expect(rate_card.attached_to_subscriptions?).to be(false)
    end

    it "is true when on a plan that has subscriptions" do
      plan = create(:plan, organization: rate_card.organization)
      create(:plan_rate_card, organization: rate_card.organization, plan:, rate_card:)
      create(:subscription, plan:, organization: rate_card.organization)

      expect(rate_card.attached_to_subscriptions?).to be(true)
    end

    it "is true when attached directly to a subscription" do
      create(:subscription_rate_card, organization: rate_card.organization, rate_card:)

      expect(rate_card.attached_to_subscriptions?).to be(true)
    end
  end

  describe "#rate_active_at" do
    subject(:rate_card) { create(:rate_card) }

    let!(:old_rate) { create(:rate_card_rate, rate_card:, effective_from: 10.days.ago.beginning_of_day) }
    let!(:new_rate) { create(:rate_card_rate, rate_card:, effective_from: 2.days.ago.beginning_of_day) }

    it "returns the rate that was active at the given time" do
      expect(rate_card.rate_active_at(5.days.ago)).to eq(old_rate)
      expect(rate_card.rate_active_at(1.day.ago)).to eq(new_rate)
    end

    it "returns nil before the first rate" do
      expect(rate_card.rate_active_at(11.days.ago)).to be_nil
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Plan do
  subject(:plan) { build(:plan, trial_period: 3) }

  it { expect(described_class).to be_soft_deletable }

  it do
    expect(subject).to have_one(:minimum_commitment)
    expect(subject).to have_one(:metadata).class_name("Metadata::ItemMetadata")
    expect(subject).to have_many(:usage_thresholds)
    expect(subject).to have_many(:commitments)
    expect(subject).to have_many(:charges).dependent(:destroy)
    expect(subject).to have_many(:charge_filters).through(:charges).source(:filters)
    expect(subject).to have_many(:billable_metrics).through(:charges)
    expect(subject).to have_many(:fixed_charges).dependent(:destroy)
    expect(subject).to have_many(:add_ons).through(:fixed_charges)
    expect(subject).to have_many(:subscriptions)
    expect(subject).to have_many(:customers).through(:subscriptions)
    expect(subject).to have_many(:children).class_name("Plan").dependent(:destroy)
    expect(subject).to have_many(:coupon_targets)
    expect(subject).to have_many(:coupons).through(:coupon_targets)
    expect(subject).to have_many(:invoices).through(:subscriptions)
    expect(subject).to have_many(:usage_thresholds)
    expect(subject).to have_many(:applied_taxes).class_name("Plan::AppliedTax").dependent(:destroy)
    expect(subject).to have_many(:taxes).through(:applied_taxes)
    expect(subject).to have_many(:entitlements).class_name("Entitlement::Entitlement").dependent(:destroy)
    expect(subject).to have_many(:entitlement_values).through(:entitlements).source(:values).class_name("Entitlement::EntitlementValue").dependent(:destroy)

    expect(subject).to define_enum_for(:interval).with_values(Plan::INTERVALS).validating(allowing_nil: true)
  end

  describe "Clickhouse associations", clickhouse: true do
    it { is_expected.to have_many(:activity_logs).class_name("Clickhouse::ActivityLog") }
  end

  it_behaves_like "paper_trail traceable"

  describe "Validations" do
    it "requires the pay_in_advance" do
      plan.pay_in_advance = nil
      expect(plan).not_to be_valid

      plan.pay_in_advance = true
      expect(plan).to be_valid
    end

    context "with a legacy plan" do
      it "requires interval and amount_cents" do
        plan.interval = nil
        plan.amount_cents = nil
        expect(plan).not_to be_valid
        expect(plan.errors.messages[:interval]).to eq(["value_is_invalid"])
        expect(plan.errors.messages[:amount_cents]).to eq(["value_is_mandatory"])
      end
    end
  end

  describe "#is_parent? and #is_child?" do
    it do
      expect(plan.is_parent?).to be true
      expect(plan.is_child?).to be false

      plan.parent_id = SecureRandom.uuid
      expect(plan.is_parent?).to be false
      expect(plan.is_child?).to be true
    end
  end

  describe "#applicable_usage_thresholds" do
    let(:plan) { create(:plan) }

    it "returns usage thresholds plan is a parent" do
      threshold = create(:usage_threshold, plan: plan)
      expect(plan.applicable_usage_thresholds).to contain_exactly(threshold)
    end

    it "returns parent usage thresholds if plan is a child" do
      create(:usage_threshold, plan: plan, amount_cents: 99_00)
      parent = create(:plan)
      threshold = create(:usage_threshold, plan: parent)
      plan.update!(parent: parent)

      expect(plan.applicable_usage_thresholds).to contain_exactly(threshold)
    end

    it "returns an empty array if neither plan nor parent has thresholds" do
      plan.update!(parent: create(:plan))
      expect(plan.applicable_usage_thresholds).to eq([])
    end
  end

  describe "#has_trial?" do
    it "returns true when trial_period" do
      expect(plan).to have_trial
    end

    context "when value is 0" do
      let(:plan) { build(:plan, trial_period: 0) }

      it "returns false" do
        expect(plan).not_to have_trial
      end
    end
  end

  describe "#charges_billed_in_monthly_split_intervals?" do
    subject(:method_call) { plan.charges_billed_in_monthly_split_intervals? }

    let(:plan) { build_stubbed(:plan, interval:, bill_charges_monthly:) }

    context "when interval is yearly" do
      let(:interval) { :yearly }

      context "when bill charges monthly is true" do
        let(:bill_charges_monthly) { true }

        it "returns true" do
          expect(subject).to be true
        end
      end

      context "when bill charges monthly is false" do
        let(:bill_charges_monthly) { false }

        it "returns false" do
          expect(subject).to be false
        end
      end

      context "when bill charges monthly is nil" do
        let(:bill_charges_monthly) { nil }

        it "returns false" do
          expect(subject).to be false
        end
      end
    end

    context "when interval is semiannual" do
      let(:interval) { :semiannual }

      context "when bill charges monthly is true" do
        let(:bill_charges_monthly) { true }

        it "returns true" do
          expect(subject).to be true
        end
      end

      context "when bill charges monthly is false" do
        let(:bill_charges_monthly) { false }

        it "returns false" do
          expect(subject).to be false
        end
      end

      context "when bill charges monthly is nil" do
        let(:bill_charges_monthly) { nil }

        it "returns false" do
          expect(subject).to be false
        end
      end
    end

    context "when interval is quarterly" do
      let(:interval) { :quarterly }

      context "when bill charges monthly is true" do
        let(:bill_charges_monthly) { true }

        it "returns false" do
          expect(subject).to be false
        end
      end

      context "when bill charges monthly is false" do
        let(:bill_charges_monthly) { false }

        it "returns false" do
          expect(subject).to be false
        end
      end

      context "when bill charges monthly is nil" do
        let(:bill_charges_monthly) { nil }

        it "returns false" do
          expect(subject).to be false
        end
      end
    end

    context "when interval is monthly" do
      let(:interval) { :monthly }

      context "when bill charges monthly is true" do
        let(:bill_charges_monthly) { true }

        it "returns false" do
          expect(subject).to be false
        end
      end

      context "when bill charges monthly is false" do
        let(:bill_charges_monthly) { false }

        it "returns false" do
          expect(subject).to be false
        end
      end

      context "when bill charges monthly is nil" do
        let(:bill_charges_monthly) { nil }

        it "returns false" do
          expect(subject).to be false
        end
      end
    end

    context "when interval is weekly" do
      let(:interval) { :weekly }

      context "when bill charges monthly is true" do
        let(:bill_charges_monthly) { true }

        it "returns false" do
          expect(subject).to be false
        end
      end

      context "when bill charges monthly is false" do
        let(:bill_charges_monthly) { false }

        it "returns false" do
          expect(subject).to be false
        end
      end

      context "when bill charges monthly is nil" do
        let(:bill_charges_monthly) { nil }

        it "returns false" do
          expect(subject).to be false
        end
      end
    end
  end

  describe "#fixed_charges_billed_in_monthly_split_intervals?" do
    subject(:method_call) { plan.fixed_charges_billed_in_monthly_split_intervals? }

    let(:plan) { build_stubbed(:plan, interval:, bill_fixed_charges_monthly:) }

    context "when interval is yearly" do
      let(:interval) { :yearly }

      context "when bill fixed charges monthly is true" do
        let(:bill_fixed_charges_monthly) { true }

        it { is_expected.to be true }
      end

      context "when bill fixed charges monthly is false" do
        let(:bill_fixed_charges_monthly) { false }

        it { is_expected.to be false }
      end

      context "when bill fixed charges monthly is nil" do
        let(:bill_fixed_charges_monthly) { nil }

        it { is_expected.to be false }
      end
    end

    context "when interval is semiannual" do
      let(:interval) { :semiannual }

      context "when bill fixed charges monthly is true" do
        let(:bill_fixed_charges_monthly) { true }

        it { is_expected.to be true }
      end

      context "when bill fixed charges monthly is false" do
        let(:bill_fixed_charges_monthly) { false }

        it { is_expected.to be false }
      end

      context "when bill fixed charges monthly is nil" do
        let(:bill_fixed_charges_monthly) { nil }

        it { is_expected.to be false }
      end
    end

    context "when interval is quarterly" do
      let(:interval) { :quarterly }

      context "when bill fixed charges monthly is true" do
        let(:bill_fixed_charges_monthly) { true }

        it { is_expected.to be false }
      end

      context "when bill fixed charges monthly is false" do
        let(:bill_fixed_charges_monthly) { false }

        it { is_expected.to be false }
      end

      context "when bill fixed charges monthly is nil" do
        let(:bill_fixed_charges_monthly) { nil }

        it { is_expected.to be false }
      end
    end

    context "when interval is monthly" do
      let(:interval) { :monthly }

      context "when bill fixed charges monthly is true" do
        let(:bill_fixed_charges_monthly) { true }

        it { is_expected.to be false }
      end

      context "when bill fixed charges monthly is false" do
        let(:bill_fixed_charges_monthly) { false }

        it { is_expected.to be false }
      end

      context "when bill fixed charges monthly is nil" do
        let(:bill_fixed_charges_monthly) { nil }

        it { is_expected.to be false }
      end
    end

    context "when interval is weekly" do
      let(:interval) { :weekly }

      context "when bill fixed charges monthly is true" do
        let(:bill_fixed_charges_monthly) { true }

        it { is_expected.to be false }
      end

      context "when bill fixed charges monthly is false" do
        let(:bill_fixed_charges_monthly) { false }

        it { is_expected.to be false }
      end

      context "when bill fixed charges monthly is nil" do
        let(:bill_fixed_charges_monthly) { nil }

        it { is_expected.to be false }
      end
    end
  end

  describe "#charges_or_fixed_charges_billed_in_monthly_split_intervals?" do
    subject(:method_call) { plan.charges_or_fixed_charges_billed_in_monthly_split_intervals? }

    let(:plan) { build_stubbed(:plan, interval: :yearly, bill_charges_monthly:, bill_fixed_charges_monthly:) }

    context "when charges and fixed charges billed in monthly split intervals are false" do
      let(:bill_charges_monthly) { false }
      let(:bill_fixed_charges_monthly) { false }

      it { is_expected.to be false }
    end

    context "when charges and fixed charges billed in monthly split intervals are true" do
      let(:bill_charges_monthly) { true }
      let(:bill_fixed_charges_monthly) { true }

      it { is_expected.to be true }
    end

    context "when charges billed in monthly split intervals is true" do
      let(:bill_charges_monthly) { true }
      let(:bill_fixed_charges_monthly) { false }

      it { is_expected.to be true }
    end

    context "when fixed charges billed in monthly split intervals is true" do
      let(:bill_charges_monthly) { false }
      let(:bill_fixed_charges_monthly) { true }

      it { is_expected.to be true }
    end
  end

  describe "#yearly_amount_cents" do
    subject(:method_call) { plan.yearly_amount_cents }

    let(:plan) { build_stubbed(:plan, interval:, amount_cents: 100) }

    context "when plan is yearly" do
      let(:interval) { :yearly }

      it "returns the correct amount" do
        expect(subject).to eq(100)
      end
    end

    context "when plan is monthly" do
      let(:interval) { :monthly }

      it "returns the correct amount" do
        expect(subject).to eq(1200)
      end
    end

    context "when plan is weekly" do
      let(:interval) { :weekly }

      it "returns the correct amount" do
        expect(subject).to eq(5200)
      end
    end

    context "when plan is quarterly" do
      let(:interval) { :quarterly }

      it "returns the correct amount" do
        expect(subject).to eq(400)
      end
    end

    context "when plan is semiannual" do
      let(:interval) { :semiannual }

      it "returns the correct amount" do
        expect(subject).to eq(200)
      end
    end
  end

  describe "#invoice_name" do
    subject(:plan_invoice_name) { plan.invoice_name }

    context "when invoice display name is blank" do
      let(:plan) { build_stubbed(:plan, invoice_display_name: [nil, ""].sample) }

      it "returns name" do
        expect(plan_invoice_name).to eq(plan.name)
      end
    end

    context "when invoice display name is present" do
      let(:plan) { build_stubbed(:plan) }

      it "returns invoice display name" do
        expect(plan_invoice_name).to eq(plan.invoice_display_name)
      end
    end
  end

  describe "#active_subscriptions_count" do
    let(:plan) { create(:plan) }
    let(:organization) { plan.organization }
    let(:customer) { create(:customer, organization:) }
    let(:overridden_plan) { create(:plan, organization:, parent: plan) }

    it "counts active subscriptions on the plan and all its overrides" do
      create_list(:subscription, 2, plan:, customer:)
      create_list(:subscription, 3, plan: overridden_plan, customer:)
      another_override = create(:plan, organization:, parent: plan)
      create(:subscription, plan: another_override, customer:)

      expect(plan.active_subscriptions_count).to eq(6)
    end

    it "excludes non-active subscriptions on the plan and its overrides" do
      [plan, overridden_plan].each do |subscription_plan|
        create(:subscription, plan: subscription_plan, customer:)
        %i[pending terminated canceled incomplete].each do |status|
          create(:subscription, status, plan: subscription_plan, customer:)
        end
      end

      expect(plan.active_subscriptions_count).to eq(2)
    end

    it "excludes discarded overrides and subscriptions on unrelated plans" do
      discarded_override = create(:plan, organization:, parent: plan, deleted_at: Time.current)
      unrelated_plan = create(:plan, organization:)
      [discarded_override, unrelated_plan].each do |subscription_plan|
        create(:subscription, plan: subscription_plan, customer:)
      end
      create(:subscription)

      expect(plan.active_subscriptions_count).to eq(0)
    end

    it "returns the direct count when there are no overrides" do
      create(:subscription, plan:, customer:)

      expect(plan.active_subscriptions_count).to eq(1)
    end

    it "returns zero when there are no subscriptions" do
      overridden_plan

      expect(plan.active_subscriptions_count).to eq(0)
    end

    it "counts subscriptions on an override without counting its parent or siblings" do
      create(:subscription, plan:, customer:)
      create_list(:subscription, 2, plan: overridden_plan, customer:)
      sibling = create(:plan, organization:, parent: plan)
      create(:subscription, plan: sibling, customer:)

      expect(overridden_plan.active_subscriptions_count).to eq(2)
    end
  end

  describe "#customers_count" do
    let(:customer) { create(:customer) }
    let(:plan) { create(:plan) }

    it "returns the number of impacted customers" do
      create(:subscription, customer:, plan:)
      overridden_plan = create(:plan, parent_id: plan.id)
      customer2 = create(:customer, organization: plan.organization)
      create(:subscription, customer: customer2, plan: overridden_plan)

      expect(plan.customers_count).to eq(2)
    end
  end

  describe "#draft_invoices_count" do
    let(:plan) { create(:plan) }
    let(:organization) { plan.organization }
    let(:customer) { create(:customer, organization:) }
    let(:overridden_plan) { create(:plan, organization:, parent: plan) }

    it "returns the number of draft invoices for the plan and its overrides" do
      subscription = create(:subscription, plan:, customer:)
      invoice = create(:invoice, :draft, customer:)
      create(:invoice_subscription, invoice:, subscription:)

      subscription2 = create(:subscription, plan: overridden_plan, customer:)
      invoice2 = create(:invoice, :draft, customer:)
      create(:invoice_subscription, invoice: invoice2, subscription: subscription2)

      expect(plan.draft_invoices_count).to eq(2)
    end

    it "counts an invoice shared by multiple override subscriptions once" do
      invoice = create(:invoice, :draft, customer:)
      another_override = create(:plan, organization:, parent: plan)
      [overridden_plan, overridden_plan, another_override].each do |child|
        subscription = create(:subscription, plan: child, customer:)
        create(:invoice_subscription, invoice:, subscription:)
      end

      expect(plan.draft_invoices_count).to eq(1)
    end

    it "excludes finalized invoices and discarded overrides" do
      [plan, overridden_plan].each do |invoice_plan|
        subscription = create(:subscription, plan: invoice_plan, customer:)
        invoice = create(:invoice, status: :finalized, customer:)
        create(:invoice_subscription, invoice:, subscription:)
      end
      discarded_plan = create(:plan, organization:, parent: plan, deleted_at: Time.current)
      subscription = create(:subscription, plan: discarded_plan, customer:)
      invoice = create(:invoice, :draft, customer:)
      create(:invoice_subscription, invoice:, subscription:)

      expect(plan.draft_invoices_count).to eq(0)
    end

    it "excludes invoices belonging to another organization" do
      invoice = create(:invoice, :draft)
      [plan, overridden_plan].each do |invoice_plan|
        subscription = create(:subscription, plan: invoice_plan, customer:)
        create(:invoice_subscription, invoice:, subscription:)
      end

      expect(plan.draft_invoices_count).to eq(0)
    end

    it "returns zero when there are no invoices or overrides" do
      expect(plan.draft_invoices_count).to eq(0)
    end
  end

  describe "#pay_in_arrears?" do
    context "when pay_in_advance is true" do
      let(:plan) { build(:plan, :pay_in_advance) }

      it { expect(plan.pay_in_arrears?).to be(false) }
    end

    context "when pay_in_advance is false" do
      let(:plan) { build(:plan) }

      it { expect(plan.pay_in_arrears?).to be(true) }
    end
  end
end

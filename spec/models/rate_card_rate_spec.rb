# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCardRate do
  subject(:rate_card_rate) { build(:rate_card_rate) }

  it_behaves_like "paper_trail traceable"

  describe "enums" do
    it do
      expect(rate_card_rate).to define_enum_for(:rate_model)
        .backed_by_column_of_type(:enum)
        .validating(allowing_nil: true)
        .with_values(
          standard: "standard",
          graduated: "graduated",
          package: "package",
          percentage: "percentage",
          volume: "volume",
          graduated_percentage: "graduated_percentage",
          custom: "custom",
          dynamic: "dynamic"
        )

      expect(rate_card_rate).to define_enum_for(:billing_interval_unit)
        .backed_by_column_of_type(:enum)
        .validating(allowing_nil: true)
        .with_values(day: "day", week: "week", month: "month", year: "year")
    end
  end

  describe "associations" do
    it do
      expect(rate_card_rate).to belong_to(:organization)
      expect(rate_card_rate).to belong_to(:rate_card)
    end
  end

  describe "#status" do
    let(:rate_card) { create(:rate_card) }
    let(:organization) { rate_card.organization }

    it "derives the status from the card timeline" do
      terminated = create(:rate_card_rate, organization:, rate_card:, effective_from: 2.months.ago.beginning_of_day)
      active = create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.ago.beginning_of_day)
      pending = create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.from_now.beginning_of_day)

      expect(terminated.status).to eq("terminated")
      expect(terminated).to be_terminated
      expect(active.status).to eq("active")
      expect(active).to be_active
      expect(pending.status).to eq("pending")
      expect(pending).to be_pending
    end
  end

  describe "Scopes" do
    describe ".pending and .effective" do
      it "splits rates around the current time" do
        rate_card = create(:rate_card)
        effective = create(:rate_card_rate, organization: rate_card.organization, rate_card:, effective_from: 1.month.ago.beginning_of_day)
        pending = create(:rate_card_rate, organization: rate_card.organization, rate_card:, effective_from: 1.month.from_now.beginning_of_day)

        expect(described_class.pending).to eq([pending])
        expect(described_class.effective).to eq([effective])
      end
    end
  end

  describe "validations" do
    describe "effective_from normalization" do
      it "canonicalizes a time component to midnight on an arrears card" do
        card = create(:rate_card, billing_timing: "arrears")
        rate = create(:rate_card_rate, rate_card: card, effective_from: "2026-12-01T17:00:00Z")

        expect(rate.effective_from).to eq(Time.zone.parse("2026-12-01T00:00:00Z"))
      end

      it "stores a date and a midnight datetime as midnight on an arrears card" do
        card = create(:rate_card, billing_timing: "arrears")
        midnight = Time.zone.parse("2026-12-01T00:00:00Z")

        from_date = create(:rate_card_rate, rate_card: card, effective_from: "2026-12-01")
        from_datetime = create(:rate_card_rate, rate_card: card, code: "other", effective_from: "2026-12-02T00:00:00Z")

        expect(from_date.effective_from).to eq(midnight)
        expect(from_datetime.effective_from).to eq(midnight + 1.day)
      end

      it "keeps the full instant on an advance card" do
        card = create(:rate_card, billing_timing: "advance")
        rate = create(:rate_card_rate, rate_card: card, effective_from: "2026-12-01T17:00:00Z")

        expect(rate.effective_from).to eq(Time.zone.parse("2026-12-01T17:00:00Z"))
      end

      it "caps arrears at one rate per day through the uniqueness rule" do
        card = create(:rate_card, billing_timing: "arrears")
        create(:rate_card_rate, rate_card: card, effective_from: "2026-12-01")
        duplicate = build(:rate_card_rate, rate_card: card, code: "other", effective_from: "2026-12-01T17:00:00Z")
        duplicate.valid?
        expect(duplicate.errors.where(:effective_from, :value_already_exist)).to be_present
      end
    end

    it { is_expected.to validate_presence_of(:effective_from) }

    describe "effective_from parseability" do
      it "rejects an unparseable value as invalid rather than missing" do
        rate = build(:rate_card_rate, effective_from: "hello")
        rate.valid?
        expect(rate.errors.where(:effective_from).map(&:type)).to eq([:invalid])
      end

      it "rejects an impossible date as invalid rather than missing" do
        rate = build(:rate_card_rate, effective_from: "2026-13-45")
        rate.valid?
        expect(rate.errors.where(:effective_from).map(&:type)).to eq([:invalid])
      end

      it "keeps a missing value on the presence error" do
        rate = build(:rate_card_rate, effective_from: nil)
        rate.valid?
        expect(rate.errors.where(:effective_from).map(&:type)).to eq([:blank])
      end
    end

    describe "rate_model compatibility" do
      let(:organization) { create(:organization) }

      def rate_for(product_type:, rate_model:, billing_timing: "arrears", proration: false, metric: nil)
        item = create(:product, organization:, product_type:, billable_metric: metric)
        rate_card = create(:rate_card, organization:, product: item, billing_timing:, proration:)
        build(:rate_card_rate, organization:, rate_card:, rate_model:)
      end

      it "rejects models outside standard/graduated/volume on fixed items" do
        %w[package percentage graduated_percentage custom dynamic].each do |model|
          rate = rate_for(product_type: "fixed", rate_model: model)
          rate.valid?
          expect(rate.errors.where(:rate_model)).to be_present, "expected #{model} to be rejected"
          expect(rate.errors.first.type.to_s).to eq("not_allowed_for_product")
        end

        %w[standard graduated volume].each do |model|
          rate = rate_for(product_type: "fixed", rate_model: model)
          rate.valid?
          expect(rate.errors.where(:rate_model)).to be_empty, "expected #{model} to be allowed"
        end
      end

      it "rejects volume on an advance card" do
        rate = rate_for(product_type: "fixed", billing_timing: "advance", rate_model: "volume")
        rate.valid?
        expect(rate.errors.where(:rate_model, :not_allowed_for_billing_timing)).to be_present
      end

      it "rejects advance rates on a non-payable-in-advance aggregation" do
        metric = create(:billable_metric, organization:, aggregation_type: "max_agg", field_name: "amount")
        rate = rate_for(product_type: "usage", billing_timing: "advance", metric:, rate_model: "standard")
        rate.valid?
        expect(rate.errors.where(:rate_model, :not_allowed_for_aggregation_type)).to be_present
      end

      it "applies the v1 proration matrix" do
        recurring = create(:billable_metric, organization:, aggregation_type: "sum_agg", recurring: true, field_name: "amount")
        rate = rate_for(product_type: "usage", proration: true, metric: recurring, rate_model: "percentage")
        rate.valid?
        expect(rate.errors.where(:rate_model, :not_allowed_with_proration)).to be_present

        allowed = rate_for(product_type: "usage", proration: true, metric: recurring, rate_model: "standard")
        allowed.valid?
        expect(allowed.errors.where(:rate_model)).to be_empty
      end

      it "rejects percentage models on latest aggregation as a compatibility error" do
        latest = create(:billable_metric, organization:, aggregation_type: "latest_agg", field_name: "amount")

        %w[percentage graduated_percentage].each do |model|
          rate = rate_for(product_type: "usage", metric: latest, rate_model: model)
          rate.valid?
          expect(rate.errors.where(:rate_model, :not_allowed_for_aggregation_type)).to be_present, "expected #{model} rejected"
          expect(rate.errors.where(:rate_properties)).to be_empty
        end
      end

      it "restricts dynamic to sum aggregation" do
        sum = create(:billable_metric, organization:, aggregation_type: "sum_agg", field_name: "amount")
        count = create(:billable_metric, organization:, aggregation_type: "count_agg")

        allowed = rate_for(product_type: "usage", metric: sum, rate_model: "dynamic")
        allowed.valid?
        expect(allowed.errors.where(:rate_model)).to be_empty

        rejected = rate_for(product_type: "usage", metric: count, rate_model: "dynamic")
        rejected.valid?
        expect(rejected.errors.where(:rate_model, :not_allowed_for_aggregation_type)).to be_present
      end

      it "applies the proration matrix to fixed items" do
        allowed = rate_for(product_type: "fixed", proration: true, rate_model: "graduated")
        allowed.valid?
        expect(allowed.errors.where(:rate_model)).to be_empty

        rejected = rate_for(product_type: "fixed", proration: true, billing_timing: "advance", rate_model: "graduated")
        rejected.valid?
        expect(rejected.errors.where(:rate_model, :not_allowed_with_proration)).to be_present
      end

      it "rejects a minimum spending on advance cards" do
        rate = rate_for(product_type: "fixed", billing_timing: "advance", rate_model: "standard")
        rate.min_amount_cents = 100
        rate.valid?
        expect(rate.errors.where(:min_amount_cents, :not_allowed_for_billing_timing)).to be_present

        arrears = rate_for(product_type: "fixed", rate_model: "standard")
        arrears.min_amount_cents = 100
        arrears.valid?
        expect(arrears.errors.where(:min_amount_cents)).to be_empty
      end

      it "validates percentage properties on usage items without crashing" do
        metric = create(:billable_metric, organization:, aggregation_type: "sum_agg", field_name: "amount")
        rate = rate_for(product_type: "usage", metric:, rate_model: "percentage")
        rate.rate_properties = {"rate" => "1"}
        expect(rate).to be_valid
      end
    end

    it { is_expected.to validate_presence_of(:rate_model) }
    it { is_expected.to validate_presence_of(:billing_interval_unit) }

    it { is_expected.to validate_numericality_of(:min_amount_cents).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:billing_interval_count).is_greater_than_or_equal_to(1) }

    describe "code" do
      it { is_expected.to validate_presence_of(:code) }

      it "rejects a duplicate code on the same card" do
        rate = create(:rate_card_rate, code: "launch_price")
        duplicate = build(
          :rate_card_rate,
          rate_card: rate.rate_card,
          organization: rate.organization,
          effective_from: 1.month.from_now.beginning_of_day,
          code: "launch_price"
        )
        duplicate.valid?

        expect(duplicate.errors.where(:code, :taken)).to be_present
      end
    end

    describe "effective_from placement" do
      let(:rate_card) { create(:rate_card) }

      around { |example| travel_to(Time.zone.parse("2026-06-15")) { example.run } }

      before do
        create(:rate_card_rate, rate_card:, effective_from: Time.zone.parse("2026-01-01"))
        create(:rate_card_rate, rate_card:, effective_from: Time.zone.parse("2026-09-01"))
      end

      it "allows a rate between the active rate and a pending rate" do
        rate = build(:rate_card_rate, rate_card:, effective_from: Time.zone.parse("2026-07-01"))
        expect(rate).to be_valid
      end

      it "allows a rate after the latest pending rate" do
        rate = build(:rate_card_rate, rate_card:, effective_from: Time.zone.parse("2026-10-01"))
        expect(rate).to be_valid
      end

      it "rejects a rate at or before the active rate" do
        rate = build(:rate_card_rate, rate_card:, effective_from: Time.zone.parse("2025-12-01"))
        rate.valid?
        expect(rate.errors.added?(:effective_from, :must_be_after_active_rate)).to be(true)
      end

      it "rejects a rate sharing an existing rate timestamp" do
        rate = build(:rate_card_rate, rate_card:, effective_from: Time.zone.parse("2026-09-01"))
        rate.valid?
        expect(rate.errors.added?(:effective_from, :value_already_exist)).to be(true)
      end
    end

    describe "applied_pricing_unit_conversion_rate" do
      it "is required when the card carries an applied_pricing_unit_code" do
        rate_card = create(:rate_card, applied_pricing_unit_code: "credits")
        rate = build(:rate_card_rate, rate_card:, applied_pricing_unit_conversion_rate: nil)
        rate.valid?
        expect(rate.errors.added?(:applied_pricing_unit_conversion_rate, :blank)).to be(true)
      end

      it "is not required when the card has no applied_pricing_unit_code" do
        rate = build(:rate_card_rate, applied_pricing_unit_conversion_rate: nil)
        rate.valid?
        expect(rate.errors.added?(:applied_pricing_unit_conversion_rate, :blank)).to be(false)
      end
    end
  end
end

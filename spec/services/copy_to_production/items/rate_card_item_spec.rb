# frozen_string_literal: true

require "rails_helper"

RSpec.describe CopyToProduction::Items::RateCardItem do
  subject(:item) { described_class.new(sandbox:, production:) }

  let(:production) { create(:organization) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production) }
  let(:rate_card) { create(:rate_card, organization: sandbox, code: "api_eur") }

  it "answers its item type and activity type" do
    expect(item.item_type).to eq("rate_card")
    expect(item.activity_type).to eq("rate_card.copied_to_production")
  end

  describe "#find_existing" do
    let(:live_rate_card) { create(:rate_card, organization: production, code: "api_eur") }

    before { live_rate_card }

    it "never reuses a production rate card" do
      expect(item.find_existing(rate_card)).to be_nil
    end
  end

  describe "#refusal" do
    let(:live_rate_card) { create(:rate_card, organization: production, code: "api_eur") }

    before { live_rate_card }

    it "answers copy_to_production_code_conflict when production uses its code" do
      expect(item.refusal(rate_card)).to eq("copy_to_production_code_conflict")
    end

    context "when the production rate card is deleted" do
      before { live_rate_card.discard! }

      it "answers nil" do
        expect(item.refusal(rate_card)).to be_nil
      end
    end

    context "with a prorated card" do
      let(:metric) { create(:billable_metric, :recurring, organization: sandbox, code: "seats", aggregation_type: "sum_agg", field_name: "seats") }
      let(:product) { create(:product, organization: sandbox, billable_metric: metric, code: "api") }
      let(:rate_card) { create(:rate_card, organization: sandbox, product:, code: "api_eur", proration: true) }
      let(:live_rate_card) { nil }

      it "answers nil when production has no metric with the code of its product's" do
        expect(item.refusal(rate_card)).to be_nil
      end

      context "when production has a recurring metric with that code" do
        before do
          create(:billable_metric, :recurring, organization: production, code: "seats", aggregation_type: "sum_agg", field_name: "seats")
        end

        it "answers nil" do
          expect(item.refusal(rate_card)).to be_nil
        end
      end

      context "when production has a metric with that code that is not recurring" do
        before { create(:billable_metric, organization: production, code: "seats") }

        it "answers copy_to_production_metric_mismatch" do
          expect(item.refusal(rate_card)).to eq("copy_to_production_metric_mismatch")
        end
      end

      context "when production has a weighted sum metric with that code" do
        before do
          create(:billable_metric, :recurring, organization: production, code: "seats", aggregation_type: "weighted_sum_agg", weighted_interval: "seconds",
            field_name: "seats")
        end

        it "answers copy_to_production_metric_mismatch" do
          expect(item.refusal(rate_card)).to eq("copy_to_production_metric_mismatch")
        end
      end

      context "when the live product with its product's code bills another metric" do
        before do
          create(:billable_metric, :recurring, organization: production, code: "seats", aggregation_type: "sum_agg", field_name: "seats")
          create(:product, organization: production, code: "api", billable_metric: create(:billable_metric, organization: production))
        end

        it "reads that metric" do
          expect(item.refusal(rate_card)).to eq("copy_to_production_metric_mismatch")
        end
      end
    end
  end

  describe "#dependencies" do
    let(:pricing_unit) { create(:pricing_unit, organization: sandbox, code: "credits") }
    let(:vat) { create(:tax, organization: sandbox, code: "vat") }
    let(:gst) { create(:tax, organization: sandbox, code: "gst") }

    before do
      rate_card.update!(applied_pricing_unit_code: pricing_unit.code)
      create(:rate_card_applied_tax, rate_card:, tax: vat)
      create(:rate_card_applied_tax, rate_card:, tax: gst)
    end

    it "lists its taxes by code, then its pricing unit" do
      expect(item.dependencies(rate_card)).to eq([["tax", gst], ["tax", vat], ["pricing_unit", pricing_unit]])
    end
  end

  describe "#copy!" do
    let(:product) { create(:product, :fixed, organization: sandbox, code: "seat") }
    let(:rate_card) { create(:rate_card, organization: sandbox, product:, code: "seat_eur") }
    let(:live_product) { create(:product, :fixed, organization: production, code: "seat") }
    let(:copy) { item.copy!(rate_card, {["product", product.id] => live_product}) }

    around { |test| travel_to(Time.zone.parse("2026-11-23 10:30:00")) { test.run } }

    context "with superseded, active and pending rates" do
      before do
        create(:rate_card_rate, organization: sandbox, rate_card:, code: "launch", effective_from: Time.zone.parse("2026-08-23"))
        create(:rate_card_rate, organization: sandbox, rate_card:, code: "current", effective_from: Time.zone.parse("2026-10-23"))
        create(:rate_card_rate, organization: sandbox, rate_card:, code: "next", effective_from: Time.zone.parse("2026-12-23"))
      end

      it "starts production at the active rate, effective from now, and keeps the pending rates" do
        # Arrears rates apply per whole day: now becomes the start of the copy's day.
        expect(copy.rates.order(:effective_from).map { [it.code, it.effective_from] }).to eq(
          [["current", Time.zone.parse("2026-11-23")], ["next", Time.zone.parse("2026-12-23")]]
        )
      end
    end

    context "with an advance rate card" do
      let(:rate_card) { create(:rate_card, :advance, organization: sandbox, product:, code: "seat_eur") }

      before { create(:rate_card_rate, organization: sandbox, rate_card:, code: "current", effective_from: Time.zone.parse("2026-10-23 08:00")) }

      it "makes the active rate effective from the instant of the copy" do
        expect(copy.rates.map { [it.code, it.effective_from] }).to eq([["current", Time.zone.parse("2026-11-23 10:30:00")]])
      end
    end

    context "with pending rates only" do
      before do
        create(:rate_card_rate, organization: sandbox, rate_card:, code: "next", effective_from: Time.zone.parse("2026-12-23"))
        create(:rate_card_rate, organization: sandbox, rate_card:, code: "later", effective_from: Time.zone.parse("2027-01-23"))
      end

      it "copies them all with their dates" do
        expect(copy.rates.order(:effective_from).map { [it.code, it.effective_from] }).to eq(
          [["next", Time.zone.parse("2026-12-23")], ["later", Time.zone.parse("2027-01-23")]]
        )
      end
    end
  end
end

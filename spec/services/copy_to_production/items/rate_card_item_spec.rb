# frozen_string_literal: true

require "rails_helper"

RSpec.describe CopyToProduction::Items::RateCardItem do
  subject(:item) { described_class.new(sandbox:, production:) }

  let(:production) { create(:organization) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production) }
  let(:rate_card) { create(:rate_card, organization: sandbox, code: "api_eur") }

  # The product and its filter are remapped.
  it_behaves_like "a copy to production item copying every column", RateCard,
    left_out: %w[product_filter_id product_id]
  it_behaves_like "a copy to production item copying every column", RateCardRate,
    attributes: described_class::RATE_ATTRIBUTES, left_out: %w[rate_card_id]

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

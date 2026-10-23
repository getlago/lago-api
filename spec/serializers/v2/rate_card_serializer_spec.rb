# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::RateCardSerializer do
  subject(:payload) { described_class.new(rate_card, options).serialize }

  let(:organization) { create(:organization) }
  let(:product) { create(:product, organization:, code: "api") }
  let(:product_filter) { create(:product_filter, :with_values, organization:, product:, code: "us") }
  let(:deleted_at) { nil }
  let(:rate_card) do
    create(
      :rate_card,
      organization:,
      product:,
      product_filter:,
      name: "US API calls",
      code: "api_us",
      description: "API calls from the US",
      currency: "USD",
      created_at: Time.zone.parse("2026-09-01T08:00:00Z"),
      updated_at: Time.zone.parse("2026-09-02T09:00:00Z"),
      deleted_at:
    )
  end
  let(:options) { {} }
  let(:flat_payload) do
    {
      lago_id: rate_card.id,
      product_code: "api",
      product_filter_code: "us",
      name: "US API calls",
      code: "api_us",
      description: "API calls from the US",
      currency: "USD",
      billing_timing: "arrears",
      proration: false,
      display_on_invoice: true,
      regroup_paid_fees: nil,
      applied_pricing_unit_code: nil,
      created_at: "2026-09-01T08:00:00Z",
      updated_at: "2026-09-02T09:00:00Z",
      deleted_at: nil
    }
  end

  let(:terminated_rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: 2.days.ago.beginning_of_day) }
  let(:active_rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: 1.day.ago.beginning_of_day) }
  let(:later_rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: 2.months.from_now.beginning_of_day) }
  let(:sooner_rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.from_now.beginning_of_day) }

  # Created before their links, in the reverse order: listed by the taxes instead of the links,
  # they would come the other way around.
  let(:vat) { create(:tax, organization:, created_at: 2.days.ago) }
  let(:gst) { create(:tax, organization:, created_at: 1.day.ago) }
  let(:discarded_tax) { create(:tax, organization:) }

  before do
    # The effective rates in effective_from order, since a rate must start after the active one,
    # then the pending ones out of order.
    terminated_rate
    active_rate
    later_rate
    sooner_rate
    create(:rate_card_rate, organization:, rate_card:, effective_from: 3.months.from_now.beginning_of_day, deleted_at: Time.current)
    create(:rate_card_rate, organization:)

    # Linked oldest first, the reverse of the listed order.
    create(:rate_card_applied_tax, rate_card:, tax: gst, created_at: 2.minutes.ago)
    create(:rate_card_applied_tax, rate_card:, tax: vat, created_at: 1.minute.ago)
    create(:rate_card_applied_tax, rate_card:, tax: discarded_tax)
    # Discarded directly: Taxes::DestroyService would delete the link as well.
    discarded_tax.discard!
    create(:rate_card_applied_tax, rate_card: create(:rate_card, organization:))
  end

  it "serializes the flat rate card, without expansions" do
    expect(payload).to eq(flat_payload)
  end

  context "when the rate card is deleted" do
    let(:deleted_at) { Time.zone.parse("2026-09-03T10:00:00Z") }

    it "includes the deletion timestamp" do
      expect(payload).to eq(flat_payload.merge(deleted_at: "2026-09-03T10:00:00Z"))
    end
  end

  context "with the active_rate expansion" do
    let(:options) { {includes: %i[active_rate]} }

    it "embeds the latest effective rate" do
      expect(payload).to eq(flat_payload.merge(active_rate: V2::RateCardRateSerializer.new(active_rate).serialize))
      expect(payload[:active_rate]).to include(lago_id: active_rate.id, status: "active")
    end

    context "when every rate is pending" do
      let(:terminated_rate) { nil }
      let(:active_rate) { nil }

      it "renders it as null" do
        expect(payload).to eq(flat_payload.merge(active_rate: nil))
      end
    end
  end

  context "with the taxes expansion" do
    let(:options) { {includes: %i[taxes]} }

    it "embeds the kept taxes, the latest linked first" do
      expect(payload).to eq(flat_payload.merge(taxes: [vat, gst].map { V2::TaxSerializer.new(it).serialize }))
    end
  end

  context "with the rates expansion" do
    let(:options) { {includes: %i[rates]} }

    it "embeds the kept rates as /rates lists them, the latest effective_from first" do
      expect(payload).to eq(
        flat_payload.merge(
          rates: [later_rate, sooner_rate, active_rate, terminated_rate].map { V2::RateCardRateSerializer.new(it).serialize }
        )
      )
      expect(payload[:rates].map { it.values_at(:lago_id, :status) }).to eq(
        [
          [later_rate.id, "pending"],
          [sooner_rate.id, "pending"],
          [active_rate.id, "active"],
          [terminated_rate.id, "terminated"]
        ]
      )
    end

    # Without the rates that the factories linked to it in memory, as a show finds it.
    context "when the rate card is read from the database" do
      before { rate_card.reload }

      it "reads the statuses from the rates it loads once" do
        statements = capture_sql { payload }

        # No query per status.
        expect(statements.grep(/FROM "rate_card_rates"/).size).to eq(1)
      end
    end
  end

  context "with the product expansion" do
    let(:options) { {includes: %i[product]} }

    it "embeds the flat product" do
      expect(payload).to eq(flat_payload.merge(product: V2::ProductSerializer.new(product).serialize))
      expect(payload[:product]).not_to have_key(:product_category)
    end
  end

  context "with the product_filter expansion" do
    let(:options) { {includes: %i[product_filter]} }

    it "embeds the product filter with its values" do
      expect(payload).to eq(flat_payload.merge(product_filter: V2::ProductFilterSerializer.new(product_filter).serialize))
      expect(payload[:product_filter][:values].size).to eq(1)
    end

    context "without a product filter" do
      let(:product_filter) { nil }

      it "renders it as null" do
        expect(payload).to eq(flat_payload.merge(product_filter_code: nil, product_filter: nil))
      end
    end
  end

  context "with the active_rate and rates expansions" do
    let(:options) { {includes: %i[rates active_rate]} }

    # As a show finds it: without the rates that the factories linked to it in memory.
    before { rate_card.reload }

    it "reads the active rate and the statuses from the rates it loads once" do
      statements = capture_sql { payload }
      # No query of the active rate, nor one per status.
      rate_reads = statements.grep(/FROM "rate_card_rates"/)

      expect(payload.keys.last(2)).to eq(%i[active_rate rates])
      expect(payload[:active_rate]).to eq(V2::RateCardRateSerializer.new(active_rate).serialize)
      expect(payload[:active_rate]).to eq(payload[:rates].find { it[:status] == "active" })
      expect(rate_reads.size).to eq(1)
    end

    context "when every rate is pending" do
      let(:terminated_rate) { nil }
      let(:active_rate) { nil }

      it "renders the active rate as null" do
        expect(payload[:active_rate]).to be_nil
        expect(payload[:rates].pluck(:status)).to eq(%w[pending pending])
      end
    end
  end
end

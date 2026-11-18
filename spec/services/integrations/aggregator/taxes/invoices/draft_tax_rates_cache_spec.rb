# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Taxes::Invoices::DraftTaxRatesCache do
  subject(:rates_cache) { described_class.new(integration:, payload:) }

  let(:integration) { build_stubbed(:anrok_integration) }
  let(:counter) { Yabeda.tax_providers.draft_tax_rates_cache_total }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:amounts) { [20_000, 30_000] }

  let(:payload) { anrok_payload(amounts) }

  let(:answer) do
    {
      "succeededInvoices" => [
        {
          "id" => "txn_1",
          "fees" => [
            {
              "item_id" => "id_1",
              "item_code" => "m1",
              "amount_cents" => 20_000,
              "tax_amount_cents" => 2_000,
              "tax_breakdown" => [{"name" => "State tax", "rate" => "0.10", "tax_amount" => 2_000, "type" => "tax"}]
            },
            {
              "item_id" => "id_2",
              "item_code" => "m2",
              "amount_cents" => 30_000,
              "tax_amount_cents" => 0,
              "tax_breakdown" => [{"reason" => "reverseCharge", "type" => "exempt"}]
            }
          ]
        }
      ],
      "failedInvoices" => []
    }
  end

  def anrok_payload(line_amounts, city: "Nashville", tax_number: nil, item_code: "m1", issuing_date: Date.new(2026, 11, 18), currency: "USD")
    [
      {
        "issuing_date" => issuing_date,
        "currency" => currency,
        "contact" => {
          "external_id" => "cus_123",
          "name" => "Acme",
          "address_line_1" => "1 Main St",
          "city" => city,
          "zip" => "37201",
          "country" => "US",
          "taxable" => tax_number.present?,
          "tax_number" => tax_number
        },
        "fees" => [
          {"item_key" => "key_#{line_amounts.first}", "item_id" => "id_1", "item_code" => item_code, "amount_cents" => line_amounts.first},
          {"item_key" => "key_#{line_amounts.last}", "item_id" => "id_2", "item_code" => "m2", "amount_cents" => line_amounts.last}
        ],
        "tax_date" => issuing_date
      }
    ]
  end

  def rates_for(other_payload)
    described_class.new(integration:, payload: other_payload).fetch
  end

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    allow(counter).to receive(:increment)
  end

  describe "#fetch" do
    it "returns nil before any answer is stored" do
      expect(rates_cache.fetch).to be_nil
      expect(counter).to have_received(:increment).with({provider: "anrok", outcome: :miss})
    end

    context "when an answer was stored" do
      before { rates_cache.store(answer) }

      it "prices new amounts of the same band with the stored rates" do
        # $200 at 10% and $300 exempt were stored; $250 and $350 stay in the 0-499 band
        body = rates_for(anrok_payload([25_000, 35_000]))

        expect(body).to eq(
          "succeededInvoices" => [
            {
              "fees" => [
                {
                  "item_key" => "key_25000",
                  "item_id" => "id_1",
                  "item_code" => "m1",
                  "amount_cents" => 25_000,
                  "tax_amount_cents" => 2_500, # 25_000 * 2_000 / 20_000
                  "tax_breakdown" => [{"name" => "State tax", "rate" => "0.10", "tax_amount" => 2_500, "type" => "tax"}]
                },
                {
                  "item_key" => "key_35000",
                  "item_id" => "id_2",
                  "item_code" => "m2",
                  "amount_cents" => 35_000,
                  "tax_amount_cents" => 0,
                  "tax_breakdown" => [{"reason" => "reverseCharge", "type" => "exempt"}]
                }
              ]
            }
          ],
          "failedInvoices" => []
        )
        expect(counter).to have_received(:increment).with({provider: "anrok", outcome: :hit})
      end

      it "ignores the dates" do
        expect(rates_for(anrok_payload(amounts, issuing_date: Date.new(2026, 11, 19)))).to be_present
      end

      it "asks the provider when a line moves to another band" do
        # $300 moves to $500, the first 500-wide band above it
        expect(rates_for(anrok_payload([20_000, 50_000]))).to be_nil
      end

      it "asks the provider when the customer address changes" do
        expect(rates_for(anrok_payload(amounts, city: "Memphis"))).to be_nil
      end

      it "asks the provider when the tax identification number changes" do
        expect(rates_for(anrok_payload(amounts, tax_number: "US123"))).to be_nil
      end

      it "asks the provider when a product mapping changes" do
        expect(rates_for(anrok_payload(amounts, item_code: "m3"))).to be_nil
      end

      it "asks the provider when the currency changes" do
        expect(rates_for(anrok_payload(amounts, currency: "EUR"))).to be_nil
      end

      it "asks the provider when the integration is updated" do
        updated_integration = build_stubbed(:anrok_integration, id: integration.id, updated_at: integration.updated_at + 1.second)

        expect(described_class.new(integration: updated_integration, payload:).fetch).to be_nil
      end

      it "asks the provider when one line has no stored rate" do
        other_payload = anrok_payload(amounts)
        other_payload.first["fees"] << {"item_key" => "key_3", "item_id" => "id_3", "item_code" => "m4", "amount_cents" => 100}

        expect(rates_for(other_payload)).to be_nil
      end
    end

    context "when a line has no amount" do
      let(:amounts) { [20_000, 0] }

      it "returns nil" do
        expect(rates_cache.fetch).to be_nil
      end
    end

    context "with the seller paying the taxes" do
      let(:answer) do
        {
          "succeededInvoices" => [
            {
              "fees" => [
                {"amount_cents" => 20_000, "tax_amount_cents" => 0, "tax_breakdown" => [{"name" => "Tax", "rate" => "0.10", "tax_amount" => 2_000, "type" => "tax"}]},
                {"amount_cents" => 30_000, "tax_amount_cents" => 0, "tax_breakdown" => []}
              ]
            }
          ]
        }
      end

      before { rates_cache.store(answer) }

      it "keeps the booked taxes at zero and scales the exact ones" do
        lines = rates_for(anrok_payload([40_000, 30_000])).dig("succeededInvoices", 0, "fees")

        expect(lines.first).to include(
          "tax_amount_cents" => 0,
          "tax_breakdown" => [{"name" => "Tax", "rate" => "0.10", "tax_amount" => 4_000, "type" => "tax"}] # 40_000 * 2_000 / 20_000
        )
      end
    end

    context "with an Avalara payload" do
      let(:integration) { build_stubbed(:avalara_integration) }
      let(:payload) { avalara_payload("200.0") }

      let(:answer) do
        {
          "succeededInvoices" => [
            {"fees" => [{"amount_cents" => 20_000, "tax_amount_cents" => 1_500, "tax_breakdown" => [{"name" => "Sales tax", "rate" => "0.075", "tax_amount" => 1_500, "type" => "tax"}]}]}
          ]
        }
      end

      def avalara_payload(amount)
        [
          {
            "issuing_date" => Date.new(2026, 11, 18),
            "currency" => "USD",
            "contact" => {"external_id" => "cus_123", "name" => "Acme", "city" => "Austin", "region" => "TX", "country" => "US"},
            "billing_entity" => {"city" => "Austin", "region" => "TX", "country" => "US"},
            "fees" => [{"item_key" => "key_1", "item_id" => "id_1", "item_code" => "m1", "unit" => 3, "amount" => amount}]
          }
        ]
      end

      before { rates_cache.store(answer) }

      it "reads the amount in currency units" do
        lines = rates_for(avalara_payload("300.0")).dig("succeededInvoices", 0, "fees")

        expect(lines.first).to include("amount_cents" => 30_000, "tax_amount_cents" => 2_250) # 30_000 * 1_500 / 20_000
        expect(counter).to have_received(:increment).with({provider: "avalara", outcome: :hit})
      end

      it "asks the provider when the billing entity address changes" do
        other_payload = avalara_payload("300.0")
        other_payload.first["billing_entity"]["region"] = "CA"

        expect(rates_for(other_payload)).to be_nil
      end
    end
  end

  describe "#store" do
    it "keeps the rates between 24 and 36 hours" do
      allow(cache).to receive(:write_multi).and_call_original

      rates_cache.store(answer)

      expect(cache).to have_received(:write_multi) do |_entries, expires_in:|
        expect(expires_in).to be_between(24.hours, 36.hours)
      end
    end

    it "skips a failed answer" do
      rates_cache.store({"succeededInvoices" => [], "failedInvoices" => [{"validation_errors" => {"type" => "customerAddressCouldNotResolve"}}]})

      expect(rates_cache.fetch).to be_nil
    end

    it "skips an answer that does not cover every line" do
      rates_cache.store(answer.deep_dup.tap { it["succeededInvoices"].first["fees"].pop })

      expect(rates_cache.fetch).to be_nil
    end
  end

  describe "bands" do
    def band_of(amount_cents)
      rates_cache.send(:band, BigDecimal(amount_cents) / 100)
    end

    it "is 500 wide up to 5,000, then 1,000 wide" do
      expect([0, 49_999, 50_000, 499_999, 500_000, 599_999, 600_000].map { band_of(it) }).to eq([0, 0, 1, 9, 10, 10, 11])
    end
  end
end

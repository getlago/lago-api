# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::Mrr do
  describe ".cache_key" do
    subject(:mrr_cache_key) { described_class.cache_key(organization_id, **args) }

    let(:organization_id) { SecureRandom.uuid }
    let(:billing_entity_id) { SecureRandom.uuid }
    let(:currency) { "EUR" }
    let(:months) { 12 }
    let(:date) { Date.current.strftime("%Y-%m-%d") }

    context "with no arguments" do
      let(:args) { {} }
      let(:cache_key) { "mrr/#{date}/#{organization_id}///" }

      it "returns the cache key" do
        expect(mrr_cache_key).to eq(cache_key)
      end
    end

    context "with currency and months" do
      let(:args) { {currency:, months:} }

      let(:cache_key) do
        "mrr/#{date}/#{organization_id}//#{currency}/#{months}"
      end

      it "returns the cache key" do
        expect(mrr_cache_key).to eq(cache_key)
      end

      context "with billing_entity_id" do
        let(:args) { {billing_entity_id:, currency:, months:} }
        let(:cache_key) do
          "mrr/#{date}/#{organization_id}/#{billing_entity_id}/#{currency}/#{months}"
        end

        it "returns the cache key" do
          expect(mrr_cache_key).to eq(cache_key)
        end
      end
    end

    context "with months" do
      let(:args) { {months:} }
      let(:cache_key) { "mrr/#{date}/#{organization_id}///#{months}" }

      it "returns the cache key" do
        expect(mrr_cache_key).to eq(cache_key)
      end
    end

    context "with currency" do
      let(:args) { {currency:} }
      let(:cache_key) { "mrr/#{date}/#{organization_id}//#{currency}/" }

      it "returns the cache key" do
        expect(mrr_cache_key).to eq(cache_key)
      end
    end

    context "with billing_entity_id" do
      let(:args) { {billing_entity_id:} }
      let(:cache_key) { "mrr/#{date}/#{organization_id}/#{billing_entity_id}//" }

      it "returns the cache key" do
        expect(mrr_cache_key).to eq(cache_key)
      end
    end
  end

  describe ".find_all_by" do
    subject(:mrrs) { described_class.find_all_by(organization.id, **args) }

    let_it_be(:plan) { create_default(:plan) }
    let_it_be(:organization) { create_default(:organization, created_at: 3.months.ago) }
    let_it_be(:customer) { create_default(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:) }
    let(:fee1) do
      create(:fee, subscription:, amount_cents: 100, amount_currency: "EUR", created_at: 2.months.ago, taxes_amount_cents: 10)
    end
    let(:fee2) do
      create(:fee, subscription:, amount_cents: 200, amount_currency: "EUR", created_at: 2.months.ago, taxes_amount_cents: 20)
    end
    let(:fee3) do
      create(:fee, subscription:, amount_cents: 300, amount_currency: "EUR", created_at: 1.month.ago, taxes_amount_cents: 30)
    end
    let(:fee4) do
      create(:fee, subscription:, amount_cents: 400, amount_currency: "EUR", created_at: 1.month.ago, taxes_amount_cents: 40)
    end
    let(:invoice1) do
      create(:invoice, organization:, billing_entity: billing_entity1, issuing_date: 2.months.ago, status: :finalized, fees: [fee1, fee2], customer: customer)
    end
    let(:invoice2) do
      create(:invoice, organization:, billing_entity: billing_entity2, issuing_date: 1.month.ago, status: :finalized, fees: [fee3, fee4], customer: customer)
    end
    let(:billing_entity1) { organization.default_billing_entity }

    let_it_be(:billing_entity2) { create(:billing_entity, organization: organization) }

    before do
      invoice1
      invoice2
    end

    context "with no arguments" do
      let(:args) { {} }

      it "returns all MRRs" do
        expect(mrrs).to match_array([
          hash_including({
            "amount_cents" => nil,
            "currency" => nil,
            "month" => Time.current.beginning_of_month
          }), hash_including({
            "amount_cents" => 770.0,
            "currency" => "EUR",
            "month" => Time.current.beginning_of_month - 1.month
          }), hash_including({
            "amount_cents" => 330.0,
            "currency" => "EUR",
            "month" => Time.current.beginning_of_month - 2.months
          }), hash_including({
            "amount_cents" => nil,
            "currency" => nil,
            "month" => Time.current.beginning_of_month - 3.months
          })
        ])
      end
    end

    context "with billing_entity_id" do
      let(:args) { {billing_entity_id: billing_entity1.id} }

      it "returns MRRs only for the provided billing_entity" do
        expect(mrrs).to match_array([
          hash_including({
            "amount_cents" => nil,
            "currency" => nil,
            "month" => Time.current.beginning_of_month
          }), hash_including({
            "amount_cents" => nil,
            "currency" => nil,
            "month" => Time.current.beginning_of_month - 1.month
          }), hash_including({
            "amount_cents" => 330.0,
            "currency" => "EUR",
            "month" => Time.current.beginning_of_month - 2.months
          }), hash_including({
            "amount_cents" => nil,
            "currency" => nil,
            "month" => Time.current.beginning_of_month - 3.months
          })
        ])
      end
    end
  end

  describe ".find_all_by with product fees" do
    subject(:mrrs) do
      described_class.find_all_by(organization.id, **args).select { it["amount_cents"] }
    end

    let(:args) { {} }
    let(:organization) { create(:organization, created_at: Time.zone.parse("2025-01-01")) }
    let(:billing_entity) { organization.default_billing_entity }
    let(:customer) { create(:customer, organization:) }
    let(:contract) { create(:contract, organization:, customer:) }
    let(:fixed_product) { create(:product, :fixed, organization:) }
    let(:metered_product) { create(:product, organization:) }

    def month(date)
      Time.zone.parse(date).beginning_of_month
    end

    def create_invoice(issuing_date, billing_entity: organization.default_billing_entity)
      create(:invoice, organization:, customer:, billing_entity:, issuing_date: Time.zone.parse(issuing_date), status: :finalized)
    end

    def create_product_fee(invoice:, amount_cents:, from:, to:, product: fixed_product, currency: "EUR",
      interval_unit: "month", interval_count: 1, rate_override: nil, pay_in_advance: false, contract_rate_card: nil)
      contract_rate_card ||= begin
        rate_card = create(:rate_card, organization:, product:, currency:)
        create(:contract_rate_card, organization:, contract:, rate_card:)
      end
      rate_card_rate = contract_rate_card.rate_card.rates.first || create(
        :rate_card_rate,
        organization:,
        rate_card: contract_rate_card.rate_card,
        billing_interval_unit: interval_unit,
        billing_interval_count: interval_count
      )

      create(
        :product_fee,
        invoice:,
        subscription: nil,
        contract:,
        contract_rate_card:,
        rate_card_rate:,
        rate_override:,
        invoiceable_id: product.id,
        amount_cents:,
        amount_currency: currency,
        pay_in_advance:,
        properties: {
          "from_datetime" => Time.zone.parse(from).iso8601(6),
          "to_datetime" => Time.zone.parse(to).end_of_day.iso8601(6)
        }
      )
    end

    context "with a monthly fixed product" do
      before do
        invoice = create_invoice("2025-03-01")
        create_product_fee(invoice:, amount_cents: 1000, from: "2025-02-01", to: "2025-02-28")
        create_product_fee(invoice:, amount_cents: 7777, from: "2025-02-01", to: "2025-02-28", product: metered_product)

        subscription = create(:subscription, customer:, plan: create(:plan, organization:))
        create(:fee, invoice:, subscription:, amount_cents: 500, taxes_amount_cents: 0)
      end

      it "adds the fixed product fees to the subscription fees of the issuing month" do
        expect(mrrs).to contain_exactly(
          hash_including("month" => month("2025-03-01"), "currency" => "EUR", "amount_cents" => 1500.0)
        )
      end

      context "with billing_entity_id" do
        let(:args) { {billing_entity_id: other_billing_entity.id} }
        let(:other_billing_entity) { create(:billing_entity, organization:) }

        before do
          invoice = create_invoice("2025-04-01", billing_entity: other_billing_entity)
          create_product_fee(invoice:, amount_cents: 300, from: "2025-03-01", to: "2025-03-31")
        end

        it "returns the product fees of the billing entity only" do
          expect(mrrs).to contain_exactly(
            hash_including("month" => month("2025-04-01"), "currency" => "EUR", "amount_cents" => 300.0)
          )
        end
      end

      context "with currency" do
        let(:args) { {currency: "USD"} }

        before do
          create_product_fee(invoice: create_invoice("2025-04-01"), amount_cents: 300, from: "2025-03-01", to: "2025-03-31", currency: "USD")
        end

        it "returns the product fees in the currency only" do
          expect(mrrs).to contain_exactly(
            hash_including("month" => month("2025-04-01"), "currency" => "USD", "amount_cents" => 300.0)
          )
        end
      end
    end

    context "with a quarterly fixed product billed in advance" do
      before do
        create_product_fee(
          invoice: create_invoice("2025-04-01"),
          amount_cents: 9000,
          from: "2025-04-01",
          to: "2025-06-30",
          interval_count: 3,
          pay_in_advance: true
        )
      end

      it "spreads the fee over the months of the period" do
        expect(mrrs.map { it["month"] }).to eq([month("2025-04-01"), month("2025-05-01"), month("2025-06-01")])
        expect(mrrs.map { it["amount_cents"] }).to all(be_within(50).of(3000))
        expect(mrrs.sum { it["amount_cents"] }).to be_within(0.001).of(9000)
      end
    end

    context "with a rate override changing the interval" do
      before do
        create_product_fee(
          invoice: create_invoice("2025-07-01"),
          amount_cents: 12_000,
          from: "2025-07-01",
          to: "2026-06-30",
          rate_override: create(:rate_override, organization:, billing_interval_unit: "year"),
          pay_in_advance: true
        )
      end

      it "normalizes the fee from the overridden interval" do
        expect(mrrs.size).to eq(12)
        expect(mrrs.first["month"]).to eq(month("2025-07-01"))
        expect(mrrs.map { it["amount_cents"] }).to all(be_within(50).of(1000))
        expect(mrrs.sum { it["amount_cents"] }).to be_within(0.001).of(12_000)
      end
    end

    context "with fixed products billed weekly or daily" do
      before do
        rate_card = create(:rate_card, organization:, product: fixed_product)
        contract_rate_card = create(:contract_rate_card, organization:, contract:, rate_card:)

        create_product_fee(
          invoice: create_invoice("2025-03-08"), contract_rate_card:, amount_cents: 100,
          from: "2025-03-01", to: "2025-03-07", interval_unit: "week"
        )
        create_product_fee(
          invoice: create_invoice("2025-03-15"), contract_rate_card:, amount_cents: 300,
          from: "2025-03-08", to: "2025-03-14", interval_unit: "week"
        )
        create_product_fee(
          invoice: create_invoice("2025-03-15"), amount_cents: 140,
          from: "2025-03-01", to: "2025-03-14", interval_unit: "day", interval_count: 14
        )
      end

      it "scales the average billed period of each product to a month" do
        expect(mrrs).to contain_exactly(hash_including("month" => month("2025-03-01"), "currency" => "EUR"))
        expect(mrrs.first["amount_cents"]).to be_within(0.001).of((200 * 4.33) + (140 * 30.44 / 14))
      end
    end
  end
end

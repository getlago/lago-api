# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Taxes::Invoices::DraftTaxesCacheService do
  subject(:cache_service) { described_class.new(integration:, payload:) }

  let(:integration) { build_stubbed(:anrok_integration) }
  let(:counter) { Yabeda.tax_providers.draft_taxes_cache_total }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:amount_cents) { 200 }
  let(:city) { "Paris" }
  let(:item_code) { "m1" }

  let(:payload) do
    [
      {
        "issuing_date" => Date.new(2026, 10, 11),
        "currency" => "USD",
        "contact" => {
          "external_id" => "cus_123",
          "name" => "Acme",
          "address_line_1" => "1 rue de la Paix",
          "city" => city,
          "zip" => "75002",
          "country" => "FR",
          "taxable" => false,
          "tax_number" => nil
        },
        "fees" => [
          {"item_key" => "key_1", "item_id" => "id_1", "item_code" => item_code, "amount_cents" => amount_cents},
          {"item_key" => "key_2", "item_id" => "id_2", "item_code" => "m2", "amount_cents" => 300}
        ],
        "tax_date" => Date.new(2026, 10, 11)
      }
    ]
  end

  let(:success_body) do
    {
      "succeededInvoices" => [
        {
          "fees" => [
            {"item_key" => "key_1", "item_id" => "id_1", "item_code" => "m1", "amount_cents" => 200, "tax_amount_cents" => 20, "tax_breakdown" => []},
            {"item_key" => "key_2", "item_id" => "id_2", "item_code" => "m2", "amount_cents" => 300, "tax_amount_cents" => 30, "tax_breakdown" => []}
          ]
        }
      ],
      "failedInvoices" => []
    }
  end

  let(:failure_body) do
    {"succeededInvoices" => [], "failedInvoices" => [{"validation_errors" => {"type" => "customerAddressCouldNotResolve"}}]}
  end

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    allow(counter).to receive(:increment)
  end

  describe "#cache_key" do
    let(:other_payload) do
      payload.deep_dup.tap do |transaction|
        transaction.first["fees"].each_with_index do |line, index|
          line["item_key"] = "new_key_#{index}"
          line["item_id"] = "new_id_#{index}"
        end
      end
    end

    it "ignores the line identifiers" do
      expect(cache_service.cache_key).to eq(described_class.new(integration:, payload: other_payload).cache_key)
    end

    it "is scoped to the integration" do
      expect(cache_service.cache_key).to start_with("anrok-draft-taxes/1/#{integration.id}/#{integration.updated_at.utc.iso8601(6)}/")
    end

    context "when the integration is updated within the same second" do
      let(:integration) { build_stubbed(:anrok_integration, updated_at: Time.zone.parse("2026-10-05 10:00:00.100")) }
      let(:updated_integration) { build_stubbed(:anrok_integration, id: integration.id, updated_at: Time.zone.parse("2026-10-05 10:00:00.200")) }

      it "changes" do
        expect(cache_service.cache_key).not_to eq(described_class.new(integration: updated_integration, payload:).cache_key)
      end
    end

    context "when an amount changes by one cent" do
      let(:other_payload) { payload.deep_dup.tap { |transaction| transaction.first["fees"].first["amount_cents"] = amount_cents + 1 } }

      it "changes" do
        expect(cache_service.cache_key).not_to eq(described_class.new(integration:, payload: other_payload).cache_key)
      end
    end

    context "when the customer address changes" do
      let(:other_payload) { payload.deep_dup.tap { |transaction| transaction.first["contact"]["city"] = "Lyon" } }

      it "changes" do
        expect(cache_service.cache_key).not_to eq(described_class.new(integration:, payload: other_payload).cache_key)
      end
    end

    context "when a product mapping changes" do
      let(:other_payload) { payload.deep_dup.tap { |transaction| transaction.first["fees"].first["item_code"] = "m3" } }

      it "changes" do
        expect(cache_service.cache_key).not_to eq(described_class.new(integration:, payload: other_payload).cache_key)
      end
    end

    context "when the lines come in a different order" do
      let(:other_payload) { payload.deep_dup.tap { |transaction| transaction.first["fees"].reverse! } }

      it "changes" do
        expect(cache_service.cache_key).not_to eq(described_class.new(integration:, payload: other_payload).cache_key)
      end
    end
  end

  describe "#call" do
    context "without a cached answer" do
      it "asks the provider and caches its answer" do
        result = cache_service.call { success_body }

        expect(result).to eq(success_body)
        expect(cache.read(cache_service.cache_key)).to eq(success_body)
        expect(counter).to have_received(:increment).with({provider: "anrok", outcome: :miss})
      end
    end

    context "with a cached answer" do
      let(:new_payload) do
        payload.deep_dup.tap do |transaction|
          transaction.first["fees"].each_with_index do |line, index|
            line["item_key"] = "new_key_#{index}"
            line["item_id"] = "new_id_#{index}"
          end
        end
      end

      before { described_class.new(integration:, payload:).call { success_body } }

      it "returns it without asking the provider" do
        block_called = false
        described_class.new(integration:, payload: new_payload).call { block_called = true }

        expect(block_called).to be(false)
        expect(counter).to have_received(:increment).with({provider: "anrok", outcome: :hit})
      end

      it "puts back the line identifiers of the current request" do
        result = described_class.new(integration:, payload: new_payload).call { success_body }

        expect(result.dig("succeededInvoices", 0, "fees").map { |line| line.slice("item_key", "item_id") }).to eq(
          [
            {"item_key" => "new_key_0", "item_id" => "new_id_0"},
            {"item_key" => "new_key_1", "item_id" => "new_id_1"}
          ]
        )
        expect(result.dig("succeededInvoices", 0, "fees").map { |line| line["tax_amount_cents"] }).to eq([20, 30])
      end

      it "leaves the cached answer untouched" do
        described_class.new(integration:, payload: new_payload).call { success_body }

        expect(cache.read(cache_service.cache_key)).to eq(success_body)
      end
    end

    context "when the provider answers with a failure" do
      it "does not cache it" do
        cache_service.call { failure_body }

        expect(cache.read(cache_service.cache_key)).to be_nil
      end
    end

    context "when the TTL is configured" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("LAGO_ANROK_DRAFT_TAXES_CACHE_TTL_SECONDS").and_return("60")
        allow(cache).to receive(:write).and_call_original
      end

      it "uses it" do
        cache_service.call { success_body }

        expect(cache).to have_received(:write).with(cache_service.cache_key, success_body, expires_in: 60.seconds)
      end
    end

    context "when the TTL is zero" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("LAGO_ANROK_DRAFT_TAXES_CACHE_TTL_SECONDS").and_return("0")
      end

      it "does not cache" do
        cache_service.call { success_body }

        expect(cache.read(cache_service.cache_key)).to be_nil
      end

      context "with an answer cached before the cache was disabled" do
        let(:fresh_body) { success_body.deep_dup.tap { |body| body["succeededInvoices"].first["fees"].first["tax_amount_cents"] = 25 } }

        before { cache.write(cache_service.cache_key, success_body) }

        it "asks the provider instead of serving it" do
          result = cache_service.call { fresh_body }

          expect(result).to eq(fresh_body)
          expect(counter).not_to have_received(:increment)
        end
      end
    end
  end
end

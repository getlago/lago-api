# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::InvoiceCollection, type: :model do
  describe ".cache_key" do
    subject(:invoice_collection_cache_key) { described_class.cache_key(organization_id, **args) }

    let(:organization_id) { SecureRandom.uuid }
    let(:external_customer_id) { "customer_01" }
    let(:currency) { "EUR" }
    let(:months) { 12 }
    let(:date) { Date.current.strftime("%Y-%m-%d") }

    context "with no arguments" do
      let(:args) { {} }
      let(:cache_key) { "invoice-collection/#{date}/#{organization_id}///" }

      it "returns the cache key" do
        expect(invoice_collection_cache_key).to eq(cache_key)
      end
    end

    context "with customer external id, currency and months" do
      let(:args) { {external_customer_id:, currency:, months:} }

      let(:cache_key) do
        "invoice-collection/#{date}/#{organization_id}/#{external_customer_id}/#{currency}/#{months}"
      end

      it "returns the cache key" do
        expect(invoice_collection_cache_key).to eq(cache_key)
      end
    end

    context "with months" do
      let(:args) { {months:} }

      let(:cache_key) do
        "invoice-collection/#{date}/#{organization_id}///#{months}"
      end

      it "returns the cache key" do
        expect(invoice_collection_cache_key).to eq(cache_key)
      end
    end

    context "with currency" do
      let(:args) { {currency:} }
      let(:cache_key) { "invoice-collection/#{date}/#{organization_id}//#{currency}/" }

      it "returns the cache key" do
        expect(invoice_collection_cache_key).to eq(cache_key)
      end
    end
  end

  describe ".find_all_by" do
    subject(:invoice_collections) { described_class.find_all_by(organization.id, **args) }

    let(:organization) { create(:organization, created_at: 3.months.ago) }
    let(:billing_entity1) { organization.default_billing_entity }
    let(:billing_entity2) { create(:billing_entity, organization: organization) }
    let(:invoices) {
      [
        create(:invoice, organization:, billing_entity: billing_entity1, issuing_date: 2.months.ago, total_amount_cents: 100, status: :pending),
        create(:invoice, organization:, billing_entity: billing_entity1, issuing_date: 2.months.ago, total_amount_cents: 200, status: :finalized),
        create(:invoice, organization:, billing_entity: billing_entity2, issuing_date: 1.month.ago, total_amount_cents: 300, status: :pending),
        create(:invoice, organization:, billing_entity: billing_entity2, issuing_date: 1.month.ago, total_amount_cents: 400, status: :finalized)
      ]
    }

    before { invoices }

    context "with no arguments" do
      let(:args) { {} }

      it "returns the finalized invoices collections" do
        expect(invoice_collections).to match_array([
          hash_including({"month" => Time.current.beginning_of_month - 3.months,
            "payment_status" => nil, "currency" => nil, "invoices_count" => 0, "amount_cents" => 0.0}),
          hash_including({"month" => Time.current.beginning_of_month - 2.months,
            "payment_status" => "pending", "currency" => "EUR", "invoices_count" => 1, "amount_cents" => 200.0}),
          hash_including({"month" => Time.current.beginning_of_month - 1.month,
            "payment_status" => "pending", "currency" => "EUR", "invoices_count" => 1, "amount_cents" => 400.0}),
          hash_including({"month" => Time.current.beginning_of_month,
            "payment_status" => nil, "currency" => nil, "invoices_count" => 0, "amount_cents" => 0.0})
        ])
      end
    end

    context "when billing_entity_id is provided" do
      let(:args) { {billing_entity_id: billing_entity1.id} }

      it "returns the finalized invoices collections filtered by billing_entity_id" do
        expect(invoice_collections).to match_array([
          hash_including({"month" => Time.current.beginning_of_month - 3.months,
                         "payment_status" => nil, "currency" => nil, "invoices_count" => 0, "amount_cents" => 0.0}),
          hash_including({"month" => Time.current.beginning_of_month - 2.months,
                         "payment_status" => "pending", "currency" => "EUR", "invoices_count" => 1, "amount_cents" => 200.0}),
          hash_including({"month" => Time.current.beginning_of_month - 1.month,
                         "payment_status" => nil, "currency" => nil, "invoices_count" => 0, "amount_cents" => 0.0}),
          hash_including({"month" => Time.current.beginning_of_month,
                         "payment_status" => nil, "currency" => nil, "invoices_count" => 0, "amount_cents" => 0.0})
        ])
      end
    end
  end
end

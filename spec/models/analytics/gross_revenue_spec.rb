# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::GrossRevenue, type: :model do
  describe ".cache_key" do
    subject(:gross_revenue_cache_key) { described_class.cache_key(organization_id, **args) }

    let(:organization_id) { SecureRandom.uuid }
    let(:external_customer_id) { "customer_01" }
    let(:currency) { "EUR" }
    let(:months) { 12 }
    let(:date) { Date.current.strftime("%Y-%m-%d") }

    context "with no arguments" do
      let(:args) { {} }
      let(:cache_key) { "gross-revenue/#{date}/#{organization_id}///" }

      it "returns the cache key" do
        expect(gross_revenue_cache_key).to eq(cache_key)
      end
    end

    context "with customer external id, currency and months" do
      let(:args) { {external_customer_id:, currency:, months:} }

      let(:cache_key) do
        "gross-revenue/#{date}/#{organization_id}/#{external_customer_id}/#{currency}/#{months}"
      end

      it "returns the cache key" do
        expect(gross_revenue_cache_key).to eq(cache_key)
      end
    end

    context "with customer external id" do
      let(:args) { {external_customer_id:} }

      let(:cache_key) do
        "gross-revenue/#{date}/#{organization_id}/#{external_customer_id}//"
      end

      it "returns the cache key" do
        expect(gross_revenue_cache_key).to eq(cache_key)
      end
    end

    context "with currency" do
      let(:args) { {currency:} }
      let(:cache_key) { "gross-revenue/#{date}/#{organization_id}//#{currency}/" }

      it "returns the cache key" do
        expect(gross_revenue_cache_key).to eq(cache_key)
      end
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::OverdueBalance do
  describe ".cache_key" do
    subject(:overdue_balance_cache_key) { described_class.cache_key(organization_id, **args) }

    let(:organization_id) { SecureRandom.uuid }
    let(:billing_entity_id) { SecureRandom.uuid }
    let(:external_customer_id) { "customer_01" }
    let(:currency) { "EUR" }
    let(:months) { 12 }
    let(:date) { Date.current.strftime("%Y-%m-%d") }

    context "with no arguments" do
      let(:args) { {} }
      let(:cache_key) { "overdue-balance/#{date}/#{organization_id}////" }

      it "returns the cache key" do
        expect(overdue_balance_cache_key).to eq(cache_key)
      end
    end

    context "with customer external id, currency and months" do
      let(:args) { {external_customer_id:, currency:, months:} }

      let(:cache_key) do
        "overdue-balance/#{date}/#{organization_id}//#{external_customer_id}/#{currency}/#{months}"
      end

      it "returns the cache key" do
        expect(overdue_balance_cache_key).to eq(cache_key)
      end

      context "with billing_entity_id" do
        let(:args) { {billing_entity_id:, external_customer_id:, currency:, months:} }
        let(:cache_key) do
          "overdue-balance/#{date}/#{organization_id}/#{billing_entity_id}/#{external_customer_id}/#{currency}/#{months}"
        end

        it "returns the cache key" do
          expect(overdue_balance_cache_key).to eq(cache_key)
        end
      end
    end

    context "with customer external id" do
      let(:args) { {external_customer_id:} }

      let(:cache_key) do
        "overdue-balance/#{date}/#{organization_id}//#{external_customer_id}//"
      end

      it "returns the cache key" do
        expect(overdue_balance_cache_key).to eq(cache_key)
      end
    end

    context "with currency" do
      let(:args) { {currency:} }
      let(:cache_key) { "overdue-balance/#{date}/#{organization_id}///#{currency}/" }

      it "returns the cache key" do
        expect(overdue_balance_cache_key).to eq(cache_key)
      end
    end

    context "with billing_entity_id" do
      let(:args) { {billing_entity_id:} }
      let(:cache_key) { "overdue-balance/#{date}/#{organization_id}/#{billing_entity_id}///" }

      it "returns the cache key" do
        expect(overdue_balance_cache_key).to eq(cache_key)
      end
    end
  end

  describe ".find_all_by" do
    subject(:overdue_balances) { described_class.find_all_by(organization.id, **args) }

    let(:organization) { create(:organization, created_at: 3.months.ago) }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:) }
    let(:billing_entity1) { organization.default_billing_entity }
    let(:billing_entity2) { create(:billing_entity, organization: organization) }
    let(:invoice1) do
      create(:invoice, customer:, organization:, payment_overdue: true, payment_due_date: 1.month.ago,
        total_amount_cents: 100, billing_entity: billing_entity1, issuing_date: 1.month.ago)
    end
    let(:invoice2) do
      create(:invoice, customer:, organization:, payment_overdue: false, payment_due_date: 1.month.ago,
        total_amount_cents: 200, billing_entity: billing_entity2, issuing_date: 1.month.ago)
    end
    let(:invoice3) do
      create(:invoice, customer:, organization:, payment_overdue: false, payment_due_date: 2.months.ago,
        total_amount_cents: 300, billing_entity: billing_entity1, issuing_date: 2.months.ago)
    end
    let(:invoice4) do
      create(:invoice, customer:, organization:, payment_overdue: true, payment_due_date: 2.months.ago,
        total_amount_cents: 400, billing_entity: billing_entity2, issuing_date: 2.months.ago)
    end

    before do
      invoice1
      invoice2
      invoice3
      invoice4
    end

    context "with no arguments" do
      let(:args) { {} }

      it "returns the overdue balances" do
        expect(overdue_balances).to match_array([
          hash_including({
            "month" => Time.current.beginning_of_month - 2.months,
            "currency" => "EUR",
            "amount_cents" => 400,
            "lago_invoice_ids" => "[[\"#{invoice4.id}\"]]"
          }), hash_including({
            "month" => Time.current.beginning_of_month - 1.month,
            "currency" => "EUR",
            "amount_cents" => 100,
            "lago_invoice_ids" => "[[\"#{invoice1.id}\"]]"
          })
        ])
      end
    end

    context "with billing entity id" do
      let(:args) { {billing_entity_id: billing_entity1.id} }

      it "returns the overdue balances for provided billing_entity only" do
        expect(overdue_balances).to match_array([
          hash_including({
            "month" => Time.current.beginning_of_month - 1.month,
            "currency" => "EUR",
            "amount_cents" => 100,
            "lago_invoice_ids" => "[[\"#{invoice1.id}\"]]"
          })
        ])
      end
    end

    context "with billing entity code" do
      let(:args) { {billing_entity_code: billing_entity2.code} }

      it "returns the overdue balances for provided billing_entity only" do
        expect(overdue_balances).to match_array([
          hash_including({
            "month" => Time.current.beginning_of_month - 2.months,
            "currency" => "EUR",
            "amount_cents" => 400,
            "lago_invoice_ids" => "[[\"#{invoice4.id}\"]]"
          })
        ])
      end
    end
  end
end

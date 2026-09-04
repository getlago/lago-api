# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::BillingPeriodFilters::EventMatchingService do
  subject(:service_result) { described_class.call(target_filter:, event:) }

  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, billable_metric:) }
  let(:target_filter) { Events::BillingPeriodFilters::FilterTarget.from_charge(charge:) }
  let(:payment_method) { create(:billable_metric_filter, billable_metric:, key: "payment_method", values: %i[card transfer]) }
  let(:card_type) { create(:billable_metric_filter, billable_metric:, key: "card_type", values: %i[credit debit]) }
  let(:event) do
    create(
      :event,
      organization_id: organization.id,
      code: billable_metric.code,
      properties: {"payment_method" => "card", "card_type" => "credit"}
    )
  end

  let(:broad_filter) { create(:charge_filter, charge:) }
  let(:specific_filter) { create(:charge_filter, charge:) }

  before do
    create(:charge_filter_value, values: ["card"], billable_metric_filter: payment_method, charge_filter: broad_filter)
    create(:charge_filter_value, values: ["card"], billable_metric_filter: payment_method, charge_filter: specific_filter)
    create(:charge_filter_value, values: ["credit"], billable_metric_filter: card_type, charge_filter: specific_filter)
  end

  it "returns matching filters and selects the most specific one" do
    expect(service_result.matching_filters).to match_array([broad_filter, specific_filter])
    expect(service_result.filter).to eq(specific_filter)
  end

  context "with a BillingSegment target" do
    let(:contract) { create(:contract, organization:, external_id: "contract_external_id") }
    let(:product) { create(:product, organization:, billable_metric:) }
    let(:rate_card) { create(:rate_card, organization:, product:) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
    let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card:) }
    let(:billing_segment) do
      create(
        :billing_segment,
        organization:,
        customer: contract.customer,
        contract:,
        contract_rate_card:,
        rate_card_rate:
      )
    end
    let(:target_filter) { Events::BillingPeriodFilters::FilterTarget.from_billing_segment(billing_segment:) }
    let(:event) do
      create(
        :event,
        organization_id: organization.id,
        code: billable_metric.code,
        properties: {"payment_method" => "virtual_card"}
      )
    end
    let(:product_filter) { create(:product_filter, organization:, product:) }

    before do
      create(:product_filter_value, value: nil, billable_metric_filter: payment_method, product_filter:)
    end

    it "matches a nil product filter value when the event carries the key" do
      expect(service_result.matching_filters).to eq([product_filter])
      expect(service_result.filter).to eq(product_filter)
    end

    context "when the event does not carry the key" do
      let(:event) do
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          properties: {"card_type" => "credit"}
        )
      end

      it "does not match the product filter" do
        expect(service_result.matching_filters).to be_empty
        expect(service_result.filter).to be_nil
      end
    end
  end

  context "with a Charge target using ALL_FILTER_VALUES" do
    before do
      broad_filter.values.destroy_all
      specific_filter.values.destroy_all
      specific_filter.discard!

      create(
        :charge_filter_value,
        values: [ChargeFilterValue::ALL_FILTER_VALUES],
        billable_metric_filter: payment_method,
        charge_filter: broad_filter
      )
    end

    it "keeps matching defined billable metric filter values" do
      expect(service_result.matching_filters).to eq([broad_filter])
      expect(service_result.filter).to eq(broad_filter)
    end

    context "when the event value is outside the defined billable metric filter values" do
      let(:event) do
        create(
          :event,
          organization_id: organization.id,
          code: billable_metric.code,
          properties: {"payment_method" => "cash"}
        )
      end

      it "does not treat the charge filter as a nil-value wildcard" do
        expect(service_result.matching_filters).to be_empty
        expect(service_result.filter).to be_nil
      end
    end
  end
end

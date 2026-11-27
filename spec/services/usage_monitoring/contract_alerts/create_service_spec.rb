# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ContractAlerts::CreateService, :premium do
  subject(:result) { described_class.call(organization:, contract:, params:) }

  let_it_be(:organization) { create(:organization, feature_flags: %w[product_catalog contract_alerts]) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:product) { create(:product, organization:) }
  let_it_be(:product_filter) { create(:product_filter, organization:, product:) }
  let_it_be(:contract) { create(:contract, organization:, customer:) }

  let(:params) do
    {
      alert_type: "usage_units",
      code: "opus_tokens",
      name: "Opus tokens",
      scope:,
      thresholds: [
        {code: "warn", value: "1000000"},
        {code: "high", value: "2000000", notify_on: %w[triggered resolved]},
        {code: "every_500k", value: "500000", recurring: true}
      ]
    }
  end
  let(:scope) { [entry] }
  let(:entry) { {type: "contract", product_code: product.code, product_filter_codes: [product_filter.code]} }

  def price_on(contract, product, product_filter: nil)
    rate_card = create(:rate_card, organization: contract.organization, product:, product_filter:)
    create(:contract_rate_card, organization: contract.organization, contract:, rate_card:)
  end

  before_all do
    price_on(contract, product)
    price_on(contract, product, product_filter:)
  end

  it "creates the alert and its thresholds" do
    expect(result).to be_success

    alert = result.alert
    expect(alert).to be_a(UsageMonitoring::ContractUsageUnitsAlert)
    expect(alert).to be_persisted
    expect(alert).to have_attributes(
      organization:,
      contract_external_id: contract.external_id,
      alert_type: "usage_units",
      code: "opus_tokens",
      name: "Opus tokens",
      product:,
      product_filter:,
      with_product_filters: false,
      direction: "increasing",
      previous_value: 0,
      previous_windows: {},
      last_processed_at: nil
    )
    expect(alert.thresholds.order(:value).pluck(:code, :value, :recurring, :notify_on)).to eq([
      ["every_500k", 500_000, true, %w[triggered]],
      ["warn", 1_000_000, false, %w[triggered]],
      ["high", 2_000_000, false, %w[triggered resolved]]
    ])
    expect(alert.all_triggered_alerts).to be_empty
  end

  it "tracks the contract once the alert is committed, so the next tick evaluates it" do
    ApplicationRecord.transaction do
      expect(result).to be_success
      expect(UsageMonitoring::ContractActivity.count).to eq(0)
    end

    expect(UsageMonitoring::ContractActivity.sole).to have_attributes(organization_id: organization.id, contract_id: contract.id, enqueued: false)
  end

  context "with an amount alert on the whole contract" do
    let(:params) { super().merge(alert_type: "usage_amount") }
    let(:scope) { [] }

    it "creates the alert without a product" do
      expect(result).to be_success
      expect(result.alert).to be_a(UsageMonitoring::ContractUsageAmountAlert)
      expect(result.alert).to have_attributes(alert_type: "usage_amount", product: nil, product_filter: nil, with_product_filters: false)
    end
  end

  context "with an amount alert on the product only" do
    let(:params) { super().merge(alert_type: "usage_amount") }
    let(:entry) { {type: "contract", product_code: product.code} }

    it "creates the alert on the product's own fees" do
      expect(result).to be_success
      expect(result.alert).to be_a(UsageMonitoring::ContractUsageAmountAlert)
      expect(result.alert).to have_attributes(product:, product_filter: nil, with_product_filters: false)
    end
  end

  [true, false].each do |flag|
    context "with with_product_filters #{flag}" do
      let(:entry) { {type: "contract", product_code: product.code, with_product_filters: flag} }

      it "creates the alert on the product, and on its filters when true" do
        expect(result).to be_success
        expect(result.alert).to have_attributes(product:, product_filter: nil, with_product_filters: flag)
      end
    end
  end

  context "without a scope" do
    let(:scope) { nil }

    it "returns a validation failure on scope" do
      expect(result.error.messages).to eq({scope: ["value_is_mandatory"]})
      expect(organization.contract_alerts).to be_empty
    end
  end

  context "with usage units and an empty scope" do
    let(:scope) { [] }

    it "returns product_required_for_units on scope" do
      expect(result.error.messages).to eq({scope: ["product_required_for_units"]})
    end
  end

  context "with a scope that is not a list" do
    let(:scope) { entry }

    it "returns a validation failure on scope" do
      expect(result.error.messages).to eq({scope: ["value_is_invalid"]})
    end
  end

  context "with two entries" do
    let(:scope) { [entry, {type: "contract", product_code: product.code}] }

    it "returns a validation failure on scope with its limit" do
      expect(result.error.messages).to eq({scope: ["value_is_invalid"]})
      expect(result.error.meta).to eq({scope: {max_items: 1}})
    end
  end

  context "with an entry that is not an object" do
    let(:params) { super().merge(alert_type: "usage_amount") }
    let(:scope) { ["contract"] }

    it "returns a validation failure on the entry rather than creating an alert on the whole contract" do
      expect(result.error.messages).to eq({"scope[0]": ["value_is_invalid"]})
      expect(organization.contract_alerts).to be_empty
    end
  end

  context "with an unknown field in the entry" do
    let(:entry) { {type: "contract", product_code: product.code, product_filter_code: product_filter.code} }

    it "returns a validation failure on that field rather than creating an alert on the whole product" do
      expect(result.error.messages).to eq({"scope[0].product_filter_code": ["value_is_invalid"]})
      expect(organization.contract_alerts).to be_empty
    end
  end

  [nil, "plan"].each do |type|
    context "with type #{type.inspect}" do
      let(:entry) { super().merge(type:) }

      it "returns a validation failure on the type, with the types allowed" do
        expect(result.error.messages).to eq({"scope[0].type": ["value_is_invalid"]})
        expect(result.error.meta).to eq({"scope[0].type": {allowed_values: ["contract"]}})
      end
    end
  end

  [{product_filter_codes: ["opus"]}, {with_product_filters: false}, {}].each do |fields|
    context "with #{fields.inspect} and no product code" do
      let(:entry) { {type: "contract", **fields} }

      it "returns a validation failure on the product code" do
        expect(result.error.messages).to eq({"scope[0].product_code": ["value_is_mandatory"]})
      end
    end
  end

  context "with a product code that is not a string" do
    let(:entry) { {type: "contract", product_code: [product.code]} }

    it "returns a validation failure on the product code" do
      expect(result.error.messages).to eq({"scope[0].product_code": ["value_is_invalid"]})
    end
  end

  [true, false, nil].each do |flag|
    context "with with_product_filters #{flag.inspect} next to product_filter_codes" do
      let(:entry) { super().merge(with_product_filters: flag) }

      it "returns a validation failure on with_product_filters, as the two exclude each other" do
        expect(result.error.messages).to eq({"scope[0].with_product_filters": ["value_is_invalid"]})
      end
    end
  end

  ["no", "true", 2].each do |flag|
    context "with with_product_filters #{flag.inspect}" do
      let(:entry) { {type: "contract", product_code: product.code, with_product_filters: flag} }

      it "returns a validation failure on with_product_filters rather than widening the scope" do
        expect(result.error.messages).to eq({"scope[0].with_product_filters": ["value_is_invalid"]})
        expect(organization.contract_alerts).to be_empty
      end
    end
  end

  [[], "opus", [nil], [""], [1]].each do |codes|
    context "with product_filter_codes #{codes.inspect}" do
      let(:entry) { super().merge(product_filter_codes: codes) }

      it "returns a validation failure on product_filter_codes rather than creating an alert on the whole product" do
        expect(result.error.messages).to eq({"scope[0].product_filter_codes": ["value_is_invalid"]})
        expect(organization.contract_alerts).to be_empty
      end
    end
  end

  context "with two product filter codes" do
    let(:entry) { super().merge(product_filter_codes: [product_filter.code, "other"]) }

    it "returns a validation failure on product_filter_codes with its limit" do
      expect(result.error.messages).to eq({"scope[0].product_filter_codes": ["value_is_invalid"]})
      expect(result.error.meta).to eq({"scope[0].product_filter_codes": {max_items: 1}})
    end
  end

  context "with a pending contract" do
    let(:contract) { create(:contract, :pending, organization:, customer:) }

    before { price_on(contract, product, product_filter:) }

    it "creates the alert" do
      expect(result).to be_success
      expect(result.alert.contract_external_id).to eq(contract.external_id)
    end

    it "does not track the contract, which is not evaluated before it is active" do
      expect(result).to be_success
      expect(UsageMonitoring::ContractActivity.count).to eq(0)
    end
  end

  context "with a threshold already past at creation" do
    before { params[:thresholds] = [{code: "zero", value: 0, notify_on: %w[triggered resolved]}, {value: 10}] }

    it "records it as seeded on the contract, without a webhook" do
      expect(result).to be_success

      seeded = result.alert.all_triggered_alerts.sole
      expect(seeded).to have_attributes(kind: "seeded", contract:, current_value: 0, previous_value: 0)
      expect(seeded.crossed_thresholds).to eq([{"code" => "zero", "value" => "0.0", "recurring" => false}])
      expect(SendWebhookJob).not_to have_been_enqueued
    end
  end

  context "without a contract" do
    let(:contract) { nil }

    it "returns a not found failure" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(result.error.error_code).to eq("contract_not_found")
    end
  end

  context "without a premium license", premium: false do
    it "returns a forbidden failure" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("feature_unavailable")
    end

    it "does not track the contract" do
      result
      expect(UsageMonitoring::ContractActivity.count).to eq(0)
    end
  end

  context "without the contract_alerts flag" do
    let(:organization) { create(:organization, feature_flags: %w[product_catalog]) }
    let(:contract) { create(:contract, organization:, customer: create(:customer, organization:)) }

    it "returns a forbidden failure" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("feature_unavailable")
    end

    it "does not track the contract" do
      result
      expect(UsageMonitoring::ContractActivity.count).to eq(0)
    end
  end

  %i[terminated canceled].each do |status|
    context "with a #{status} contract" do
      let(:contract) { create(:contract, status, organization:, customer:) }

      it "returns contract_not_live" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("contract_not_live")
      end
    end
  end

  [nil, ""].each do |alert_type|
    context "with alert_type #{alert_type.inspect}" do
      before { params[:alert_type] = alert_type }

      it "returns a validation failure on alert_type" do
        expect(result.error.messages).to eq({alert_type: ["value_is_mandatory"]})
      end
    end
  end

  ["current_usage_amount", "unknown", 1].each do |alert_type|
    context "with alert_type #{alert_type.inspect}" do
      before { params[:alert_type] = alert_type }

      it "returns invalid_type" do
        expect(result.error.messages).to eq({alert_type: ["invalid_type"]})
      end
    end
  end

  context "with invalid thresholds" do
    before { params[:thresholds] = [{value: 10}, {value: "abc"}] }

    it "returns the failure of the thresholds" do
      expect(result.error.messages).to eq({thresholds: ["value_is_invalid"]})
    end
  end

  context "without thresholds" do
    before { params.delete(:thresholds) }

    it "returns a validation failure on thresholds" do
      expect(result.error.messages).to eq({thresholds: ["value_is_mandatory"]})
    end
  end

  context "with a product that the contract does not price" do
    let(:entry) { {type: "contract", product_code: create(:product, organization:).code} }

    it "returns a not found failure" do
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(result.error.resource).to eq("product")
    end
  end

  context "with a product of another organization" do
    let(:entry) { {type: "contract", product_code: "shared_code"} }

    before do
      other_organization = create(:organization)
      other_product = create(:product, organization: other_organization, code: "shared_code")
      other_contract = create(:contract, customer: create(:customer, organization: other_organization), external_id: contract.external_id)
      price_on(other_contract, other_product)
    end

    it "returns a not found failure" do
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(result.error.resource).to eq("product")
    end
  end

  context "with a product that only a terminated contract on the external id priced" do
    let(:other_product) { create(:product, organization:) }
    let(:entry) { {type: "contract", product_code: other_product.code} }

    before { price_on(create(:contract, :terminated, organization:, customer:, external_id: contract.external_id), other_product) }

    it "returns a not found failure" do
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(result.error.resource).to eq("product")
    end
  end

  context "with a product that the pending replacement on the external id prices" do
    let(:other_product) { create(:product, organization:) }
    let(:entry) { {type: "contract", product_code: other_product.code} }

    before { price_on(create(:contract, :pending, organization:, customer:, external_id: contract.external_id), other_product) }

    it "creates the alert on it" do
      expect(result).to be_success
      expect(result.alert.product).to eq(other_product)
    end
  end

  context "with a fixed product" do
    let(:fixed_product) { create(:product, :fixed, organization:) }
    let(:params) { super().merge(alert_type: "usage_amount") }
    let(:entry) { {type: "contract", product_code: fixed_product.code} }

    before { price_on(contract, fixed_product) }

    it "returns a validation failure on the product code" do
      expect(result.error.messages).to eq({"scope[0].product_code": ["value_is_invalid"]})
    end
  end

  context "with a filter of the product that the contract does not price" do
    let(:entry) { super().merge(product_filter_codes: [create(:product_filter, organization:, product:).code]) }

    it "returns a not found failure" do
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(result.error.resource).to eq("product_filter")
    end
  end

  context "with a filter of another product" do
    let(:other_product) { create(:product, organization:) }
    let(:other_filter) { create(:product_filter, organization:, product: other_product) }
    let(:entry) { super().merge(product_filter_codes: [other_filter.code]) }

    before { price_on(contract, other_product, product_filter: other_filter) }

    it "returns a not found failure" do
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(result.error.resource).to eq("product_filter")
    end
  end

  context "without a code" do
    before { params.delete(:code) }

    it "returns a validation failure on code" do
      expect(result.error.messages).to eq({code: ["value_is_mandatory"]})
    end
  end

  context "when the code is taken on the external id" do
    before do
      create(:contract_alert, organization:, contract_external_id: contract.external_id, code: "opus_tokens")
    end

    it "returns value_already_exist on code" do
      expect(result.error.messages).to eq({code: ["value_already_exist"]})
    end

    it "does not track the contract" do
      expect(result).to be_failure
      expect(UsageMonitoring::ContractActivity.count).to eq(0)
    end
  end

  context "when the code is taken on another contract" do
    before { create(:contract_alert, organization:, code: "opus_tokens") }

    it "creates the alert" do
      expect(result).to be_success
    end
  end

  context "when the scope already has an alert of this type" do
    let(:existing) do
      create(:contract_usage_units_alert, organization:, contract_external_id: contract.external_id, product:, product_filter:)
    end

    before { existing }

    it "returns alert_already_exists on base" do
      expect(result.error.messages).to eq({base: ["alert_already_exists"]})
    end

    context "when that alert is deleted" do
      before { existing.discard! }

      it "creates the alert" do
        expect(result).to be_success
      end
    end
  end

  context "when the product already has an alert of this type" do
    let(:existing_with_product_filters) { false }
    let(:entry) { {type: "contract", product_code: product.code, with_product_filters: true} }

    before do
      create(
        :contract_usage_units_alert,
        organization:,
        contract_external_id: contract.external_id,
        product:,
        with_product_filters: existing_with_product_filters
      )
    end

    it "creates the alert with the other with_product_filters" do
      expect(result).to be_success
      expect(organization.contract_alerts.where(product:, product_filter: nil).pluck(:with_product_filters)).to match_array([false, true])
    end

    context "with the same with_product_filters" do
      let(:existing_with_product_filters) { true }

      it "returns alert_already_exists on base" do
        expect(result.error.messages).to eq({base: ["alert_already_exists"]})
      end
    end
  end

  context "when the whole contract already has an alert of this type" do
    let(:params) { super().merge(alert_type: "usage_amount") }
    let(:scope) { [] }

    before { create(:contract_usage_amount_alert, organization:, contract_external_id: contract.external_id) }

    it "returns alert_already_exists on base" do
      expect(result.error.messages).to eq({base: ["alert_already_exists"]})
    end
  end

  context "when the whole contract already has an alert of the other type" do
    let(:params) { super().merge(alert_type: "usage_amount") }
    let(:scope) { [] }

    before { create(:contract_usage_units_alert, organization:, contract_external_id: contract.external_id, product:) }

    it "creates the alert" do
      expect(result).to be_success
    end
  end
end

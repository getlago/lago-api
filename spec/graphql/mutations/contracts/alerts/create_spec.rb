# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Contracts::Alerts::Create, :premium do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let_it_be(:organization, refind: true) { create(:organization, feature_flags: %w[product_catalog contract_alerts]) }
  let_it_be(:membership) { create(:membership, organization:) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:product) { create(:product, organization:) }
  let_it_be(:product_filter) { create(:product_filter, organization:, product:) }
  let_it_be(:contract) { create(:contract, organization:, customer:) }

  let(:required_permission) { "contracts:update" }
  let(:input) do
    {
      contractId: contract.id,
      alertType: "usage_units",
      code: "opus_tokens",
      name: "Opus tokens",
      scope: [entry],
      thresholds: [
        {code: "warn", value: "1000000"},
        {code: "high", value: "2000000", notifyOn: %w[triggered resolved]},
        {code: "every_500k", value: "500000", recurring: true}
      ]
    }
  end
  let(:entry) { {type: "contract", productCode: product.code, productFilterCodes: [product_filter.code]} }
  let(:mutation) do
    <<~GQL
      mutation($input: CreateContractAlertInput!) {
        createContractAlert(input: $input) {
          id alertType code name contractExternalId
          scope { type product { id } productFilters { id } withProductFilters }
          thresholds { code value recurring notifyOn }
        }
      }
    GQL
  end

  def price_on(contract, product, product_filter: nil)
    rate_card = create(:rate_card, organization: contract.organization, product:, product_filter:)
    create(:contract_rate_card, organization: contract.organization, contract:, rate_card:)
  end

  def expect_forbidden_code(code)
    expect(execution["errors"].first["extensions"]).to eq("status" => 403, "code" => code)
  end

  before_all do
    price_on(contract, product)
    price_on(contract, product, product_filter:)
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "contracts:update"

  it "creates the alert" do
    response = execution["data"]["createContractAlert"]

    expect(response).to eq(
      "id" => organization.contract_alerts.sole.id,
      "alertType" => "usage_units",
      "code" => "opus_tokens",
      "name" => "Opus tokens",
      "contractExternalId" => contract.external_id,
      "scope" => [
        {"type" => "contract", "product" => {"id" => product.id}, "productFilters" => [{"id" => product_filter.id}], "withProductFilters" => nil}
      ],
      "thresholds" => [
        {"code" => "warn", "value" => "1000000.0", "recurring" => false, "notifyOn" => ["triggered"]},
        {"code" => "high", "value" => "2000000.0", "recurring" => false, "notifyOn" => %w[triggered resolved]},
        {"code" => "every_500k", "value" => "500000.0", "recurring" => true, "notifyOn" => ["triggered"]}
      ]
    )
  end

  context "with withProductFilters on the product" do
    let(:entry) { {type: "contract", productCode: product.code, withProductFilters: true} }

    it "creates the alert on the product and its filters" do
      expect(execution["data"]["createContractAlert"]["scope"]).to eq([
        {"type" => "contract", "product" => {"id" => product.id}, "productFilters" => nil, "withProductFilters" => true}
      ])
    end
  end

  context "with an empty scope on an amount alert" do
    let(:input) { super().merge(alertType: "usage_amount", scope: []) }

    it "creates the alert on the whole contract" do
      expect(execution["data"]["createContractAlert"]["scope"]).to eq([])
      expect(organization.contract_alerts.sole).to have_attributes(product: nil, product_filter: nil)
    end
  end

  context "with an ended contract whose replacement on the external id is active" do
    let(:ended_contract) { create(:contract, :terminated, organization:, customer:, external_id: contract.external_id) }
    let(:input) { super().merge(contractId: ended_contract.id) }

    it "creates the alert on the external id" do
      expect(execution["data"]["createContractAlert"]["contractExternalId"]).to eq(contract.external_id)
      expect(organization.contract_alerts.sole.contract_external_id).to eq(contract.external_id)
    end
  end

  context "when the contract belongs to another organization" do
    let(:input) { super().merge(contractId: create(:contract).id) }

    it "returns a not found error" do
      expect_not_found(execution, details: {contract: ["not_found"]})
    end
  end

  context "when the contract is neither pending nor active" do
    let(:input) { super().merge(contractId: create(:contract, :terminated, organization:, customer:).id) }

    it "returns a contract not live error" do
      expect_forbidden_code("contract_not_live")
    end
  end

  context "without a premium license", premium: false do
    it "returns a feature unavailable error" do
      expect_forbidden_code("feature_unavailable")
    end
  end

  context "without the contract_alerts flag" do
    before { organization.update!(feature_flags: %w[product_catalog]) }

    it "returns a feature unavailable error" do
      expect_forbidden_code("feature_unavailable")
    end
  end

  context "when the organization is not on the product catalog" do
    before { organization.update!(feature_flags: organization.feature_flags - ["product_catalog"]) }

    it "returns a feature unavailable error" do
      expect_forbidden_code("feature_unavailable")
    end
  end

  context "with a product that the contract does not price" do
    let(:entry) { {type: "contract", productCode: create(:product, organization:).code} }

    it "returns a not found error" do
      expect_not_found(execution, details: {product: ["not_found"]})
    end
  end

  context "with a filter that the contract does not price for the product" do
    let(:entry) { super().merge(productFilterCodes: [create(:product_filter, organization:, product:).code]) }

    it "returns a not found error" do
      expect_not_found(execution, details: {productFilter: ["not_found"]})
    end
  end

  context "with usage units and an empty scope" do
    let(:input) { super().merge(scope: []) }

    it "returns a validation error on the scope" do
      expect_unprocessable_entity(execution, details: {scope: ["product_required_for_units"]})
    end
  end

  context "with a blank product filter code" do
    let(:entry) { super().merge(productFilterCodes: [""]) }

    it "returns a validation error on the codes" do
      expect_unprocessable_entity(execution, details: {"scope[0].productFilterCodes": ["value_is_invalid"]})
    end
  end

  context "with a fixed product" do
    let(:fixed_product) { create(:product, :fixed, organization:) }
    let(:input) { super().merge(alertType: "usage_amount") }
    let(:entry) { {type: "contract", productCode: fixed_product.code} }

    before { price_on(contract, fixed_product) }

    it "returns a validation error on the product" do
      expect_unprocessable_entity(execution, details: {"scope[0].productCode": ["value_is_invalid"]})
    end
  end

  context "with a threshold value that is not a number" do
    let(:input) { super().merge(thresholds: [{value: "abc"}]) }

    it "returns a validation error on the thresholds" do
      expect_unprocessable_entity(execution, details: {thresholds: ["value_is_invalid"]})
    end
  end

  context "with two recurring thresholds" do
    let(:input) { super().merge(thresholds: [{value: "10", recurring: true}, {value: "20", recurring: true}]) }

    it "returns a validation error on the thresholds" do
      expect_unprocessable_entity(execution, details: {thresholds: ["value_is_invalid"]})
    end
  end

  context "when the code is taken on the contract" do
    before { create(:contract_alert, organization:, contract_external_id: contract.external_id, code: "opus_tokens") }

    it "returns a validation error on the code" do
      expect_unprocessable_entity(execution, details: {code: ["value_already_exist"]})
    end
  end

  context "when the scope already has an alert of this type" do
    before do
      create(:contract_usage_units_alert, organization:, contract_external_id: contract.external_id, product:, product_filter:)
    end

    it "returns a validation error on the alert" do
      expect_unprocessable_entity(execution, details: {base: ["alert_already_exists"]})
    end
  end
end

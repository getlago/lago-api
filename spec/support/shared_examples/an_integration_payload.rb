# frozen_string_literal: true

# This is a shared example that is used to test the payload of an integration.
# It will test the fallback behavior of the integration from billing entity to organization.
#
# It expects a `build_expected_payload` method to be defined in the spec
# ```
# it_behaves_like "an integration payload", :avalara do
#   def build_expected_payload(mapping_codes, some_extra_parameter_with_defaults: false)
#     [
#       {
#         "issuing_date" => invoice.issuing_date,
#         "currency" => invoice.currency,
#         "some_extra_parameter_with_defaults" => some_extra_parameter_with_defaults,
#         "fees" => match_array([
#           {
#             "item_key" => add_on_fee.item_key,
#             "item_id" => add_on_fee.id,
#             "amount" => "2.0",
#             "unit" => 2.0,
#             "item_code" => mapping_codes.dig(:add_on, :external_id)
#           }
#         ])
#       }
#     ]
#   end
# end
# ```
#
RSpec.shared_examples "an integration payload" do |integration_type|
  let(:integration_type) { integration_type.to_sym }
  let(:mappings_on) { [:billing_entity, :organization] }
  let(:fallback_items_on) { [:billing_entity, :organization] }

  let(:organization) { create(:organization) }
  let(:billing_entity) { create(:billing_entity, organization:) }
  let(:integration) { create("#{integration_type}_integration", organization:) }
  let(:customer) { create(:customer, organization:, billing_entity:) }
  let(:integration_customer) { create("#{integration_type}_customer", customer:, integration:) }

  let(:add_on) { create(:add_on, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }

  let(:invoice) { create(:invoice, :with_subscriptions, customer:, organization:, billing_entity:) }
  let(:subscription) { invoice.subscriptions.first }
  let(:payment) { create(:payment, payable: invoice) }

  let(:add_on_fee) { create(:add_on_fee, invoice:, add_on:, units: 2, amount_cents: 200) }
  let(:billable_metric_fee) { create(:charge_fee, invoice:, billable_metric:, units: 3, amount_cents: 300) }
  let(:commitment_fee) { create(:minimum_commitment_fee, invoice:, units: 4, amount_cents: 400) }
  let(:subscription_fee) { create(:fee, invoice:, subscription:, units: 5, amount_cents: 500) }
  let(:fees) { invoice.fees }

  let(:credit_note) { create(:credit_note, customer:, invoice:) }

  let(:add_on_credit_note) { create(:credit_note_item, credit_note:, fee: add_on_fee, amount_cents: 190) }
  let(:billable_metric_credit_note) { create(:credit_note_item, credit_note:, fee: billable_metric_fee, amount_cents: 180) }
  let(:commitment_credit_note) { create(:credit_note_item, credit_note:, fee: commitment_fee, amount_cents: 170) }
  let(:subscription_credit_note) { create(:credit_note_item, credit_note:, fee: subscription_fee, amount_cents: 160) }

  let(:add_on_mapping_on_billing_entity) do
    settings = {external_id: "add_on_on_billing_entity", external_account_code: "11", external_name: "add_on_on_billing_entity"}
    create_mapping("AddOn", add_on.id, billing_entity:, settings:)
  end
  let(:billable_metric_mapping_on_billing_entity) do
    settings = {external_id: "billable_metric_on_billing_entity", external_account_code: "22", external_name: "billable_metric_on_billing_entity"}
    create_mapping("BillableMetric", billable_metric.id, billing_entity:, settings:)
  end
  let(:commitment_mapping_on_billing_entity) do
    settings = {external_id: "commitment_on_billing_entity", external_account_code: "33", external_name: "commitment_on_billing_entity"}
    create_collection_mapping(:minimum_commitment, billing_entity:, settings:)
  end
  let(:subscription_mapping_on_billing_entity) do
    settings = {external_id: "subscription_on_billing_entity", external_account_code: "44", external_name: "subscription_on_billing_entity"}
    create_collection_mapping(:subscription_fee, billing_entity:, settings:)
  end
  let(:account_mapping_on_billing_entity) do
    settings = {external_id: "account_on_billing_entity", external_account_code: "55", external_name: "account_on_billing_entity"}
    create_collection_mapping(:account, billing_entity:, settings:)
  end
  let(:fallback_item_on_billing_entity) do
    settings = {external_id: "fallback_item_on_billing_entity", external_account_code: "66", external_name: "fallback_item_on_billing_entity"}
    create_collection_mapping(:fallback_item, billing_entity:, settings:)
  end

  let(:add_on_mapping_on_organization) do
    settings = {external_id: "add_on_on_organization", external_account_code: "111", external_name: "add_on_on_organization"}
    create_mapping("AddOn", add_on.id, billing_entity: nil, settings:)
  end
  let(:billable_metric_mapping_on_organization) do
    settings = {external_id: "billable_metric_on_organization", external_account_code: "222", external_name: "billable_metric_on_organization"}
    create_mapping("BillableMetric", billable_metric.id, billing_entity: nil, settings:)
  end
  let(:commitment_mapping_on_organization) do
    settings = {external_id: "commitment_on_organization", external_account_code: "333", external_name: "commitment_on_organization"}
    create_collection_mapping(:minimum_commitment, billing_entity: nil, settings:)
  end
  let(:subscription_mapping_on_organization) do
    settings = {external_id: "subscription_on_organization", external_account_code: "444", external_name: "subscription_on_organization"}
    create_collection_mapping(:subscription_fee, billing_entity: nil, settings:)
  end
  let(:account_mapping_on_organization) do
    settings = {external_id: "account_on_organization", external_account_code: "555", external_name: "account_on_organization"}
    create_collection_mapping(:account, billing_entity: nil, settings:)
  end
  let(:fallback_item_on_organization) do
    settings = {external_id: "fallback_item_on_organization", external_account_code: "666", external_name: "fallback_item_on_organization"}
    create_collection_mapping(:fallback_item, billing_entity: nil, settings:)
  end

  let(:default_mapping_codes) do
    {
      add_on: {external_id: "add_on_on_billing_entity", external_account_code: "11", external_name: "add_on_on_billing_entity"},
      billable_metric: {external_id: "billable_metric_on_billing_entity", external_account_code: "22", external_name: "billable_metric_on_billing_entity"},
      commitment: {external_id: "commitment_on_billing_entity", external_account_code: "33", external_name: "commitment_on_billing_entity"},
      subscription: {external_id: "subscription_on_billing_entity", external_account_code: "44", external_name: "subscription_on_billing_entity"},
      account: {external_id: "account_on_billing_entity", external_account_code: "55", external_name: "account_on_billing_entity"}
    }
  end

  before do
    add_on_mapping_on_billing_entity
    billable_metric_mapping_on_billing_entity
    commitment_mapping_on_billing_entity
    subscription_mapping_on_billing_entity
    account_mapping_on_billing_entity

    add_on_mapping_on_organization
    billable_metric_mapping_on_organization
    commitment_mapping_on_organization
    subscription_mapping_on_organization
    account_mapping_on_organization

    fallback_item_on_billing_entity

    fallback_item_on_organization

    integration_customer
    add_on_credit_note
    billable_metric_credit_note
    commitment_credit_note
    subscription_credit_note

    payment
  end

  def skip_mapping?(billing_entity)
    create_mapping_for_billing_entity = (billing_entity.present? && mappings_on.include?(:billing_entity)) ||
      (billing_entity.blank? && mappings_on.include?(:organization))
    !create_mapping_for_billing_entity
  end

  def skip_fallback_item?(billing_entity)
    create_fallback_items_for_billing_entity = (billing_entity.present? && fallback_items_on.include?(:billing_entity)) ||
      (billing_entity.blank? && fallback_items_on.include?(:organization))
    !create_fallback_items_for_billing_entity
  end

  def create_mapping(mappable_type, mappable_id, billing_entity: nil, settings: {})
    return if skip_mapping?(billing_entity)

    create("#{integration_type}_mapping", integration:, mappable_type:, mappable_id:, billing_entity:, settings:)
  end

  def create_collection_mapping(mapping_type, billing_entity: nil, settings: {})
    return if mapping_type == :fallback_item && skip_fallback_item?(billing_entity)
    return if mapping_type != :fallback_item && skip_mapping?(billing_entity)

    create("#{integration_type}_collection_mapping", integration:, billing_entity:, mapping_type:, settings:)
  end

  context "when the mapping is on the billing entity" do
    it "returns the payload body" do
      expect(payload).to match build_expected_payload(default_mapping_codes)
    end
  end

  context "when the mapping is not on the billing entity but there are fallback items" do
    let(:mappings_on) { [:organization] }
    let(:fallback_items_on) { [:billing_entity] }

    it "returns the payload body" do
      fallback = {external_id: "fallback_item_on_billing_entity", external_account_code: "66", external_name: "fallback_item_on_billing_entity"}
      expect(payload).to match build_expected_payload({
        add_on: fallback,
        billable_metric: fallback,
        commitment: fallback,
        subscription: fallback,
        account: fallback
      })
    end
  end

  context "when the mapping is only on the organization" do
    let(:mappings_on) { [:organization] }
    let(:fallback_items_on) { [:organization] }

    it "returns the payload body" do
      expect(payload).to match build_expected_payload({
        add_on: {external_id: "add_on_on_organization", external_account_code: "111", external_name: "add_on_on_organization"},
        billable_metric: {external_id: "billable_metric_on_organization", external_account_code: "222", external_name: "billable_metric_on_organization"},
        commitment: {external_id: "commitment_on_organization", external_account_code: "333", external_name: "commitment_on_organization"},
        subscription: {external_id: "subscription_on_organization", external_account_code: "444", external_name: "subscription_on_organization"},
        account: {external_id: "account_on_organization", external_account_code: "555", external_name: "account_on_organization"}
      })
    end
  end

  context "when there are only fallback items on the organization" do
    let(:mappings_on) { [] }
    let(:fallback_items_on) { [:organization] }

    it "returns the payload body" do
      fallback = {external_id: "fallback_item_on_organization", external_account_code: "666", external_name: "fallback_item_on_organization"}
      expect(payload).to match build_expected_payload({
        add_on: fallback,
        billable_metric: fallback,
        commitment: fallback,
        subscription: fallback,
        account: fallback
      })
    end
  end
end

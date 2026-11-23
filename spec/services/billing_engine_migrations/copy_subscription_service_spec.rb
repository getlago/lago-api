# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::CopySubscriptionService do
  subject(:result) { described_class.call(migration:, subscription:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:shadow_organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let_it_be(:plan) { create(:plan, organization:) }
  let_it_be(:catalog_plan) { create(:catalog_plan, organization: shadow_organization) }
  let_it_be(:customer) do
    create(
      :customer,
      :with_shipping_address,
      organization:,
      billing_entity: organization.default_billing_entity,
      timezone: "America/Los_Angeles"
    )
  end

  let(:status) { "shadowing" }
  let(:started_at) { Time.zone.parse("2025-03-01 10:00:00.123456") }
  let(:subscription_at) { Time.zone.parse("2025-03-15 02:00:00") }
  let(:ending_at) { nil }
  let(:shadow_entity_code) { customer.billing_entity.code }

  let(:migration) do
    create(
      :billing_engine_migration,
      organization:,
      shadow_organization:,
      status:,
      plan_mapping: {plan.code => catalog_plan.code}
    )
  end

  let(:subscription) do
    create(
      :subscription,
      organization:,
      customer:,
      plan:,
      name: "Main subscription",
      started_at:,
      subscription_at:,
      ending_at:
    )
  end

  before { create(:billing_entity, organization: shadow_organization, code: shadow_entity_code) }

  it "creates the customer and the contract in the shadow organization" do
    expect { result }
      .to change { shadow_organization.customers.count }.by(1)
      .and change { shadow_organization.contracts.count }.by(1)

    shadow_customer = shadow_organization.customers.find_by!(external_id: customer.external_id)
    expect(shadow_customer.billing_entity.code).to eq(customer.billing_entity.code)

    expect(result).to be_success
    expect(result.contract).to have_attributes(
      organization: shadow_organization,
      customer: shadow_customer,
      catalog_plan:,
      external_id: subscription.external_id,
      code: subscription.id,
      name: "Main subscription",
      status: "active",
      billing_time: "calendar",
      started_at:,
      ended_at: nil,
      billing_anchor_date: Date.new(2025, 1, 1)
    )
  end

  it "is idempotent" do
    described_class.call(migration:, subscription:)

    expect { described_class.call(migration:, subscription:) }
      .to not_change { shadow_organization.customers.count }
      .and not_change { shadow_organization.contracts.count }
  end

  context "when the customer has a payment provider, metadata and taxes" do
    let(:customer) do
      create(
        :customer,
        :with_stripe_payment_provider,
        organization:,
        billing_entity: organization.default_billing_entity
      )
    end

    before do
      create(:customer_metadata, customer:)
      create(:customer_applied_tax, customer:, tax: create(:tax, organization:))
    end

    it "does not copy them to the shadow customer" do
      result

      shadow_customer = shadow_organization.customers.find_by!(external_id: customer.external_id)
      expect(shadow_customer.payment_provider).to be_nil
      expect(shadow_customer.payment_provider_code).to be_nil
      expect(shadow_customer.payment_provider_customers).to be_empty
      expect(shadow_customer.metadata).to be_empty
      expect(shadow_customer.taxes).to be_empty
    end
  end

  context "when the shadow organization already has the customer" do
    let(:shadow_customer) { create(:customer, organization: shadow_organization, external_id: customer.external_id) }

    before { shadow_customer }

    it "reuses it" do
      expect { result }.not_to change { shadow_organization.customers.count }

      expect(result.contract.customer).to eq(shadow_customer)
    end
  end

  context "when the shadow organization already has a live contract with the subscription external id" do
    before do
      shadow_customer = create(:customer, organization: shadow_organization, external_id: customer.external_id)
      create(:contract, :pending, organization: shadow_organization, customer: shadow_customer, external_id: subscription.external_id)
    end

    it "does not create another one" do
      expect { result }.not_to change { shadow_organization.contracts.count }

      expect(result).to be_success
      expect(result.contract).to be_nil
    end
  end

  context "when the shadow organization only has a terminated contract with the subscription external id" do
    before do
      shadow_customer = create(:customer, organization: shadow_organization, external_id: customer.external_id)
      create(:contract, :terminated, organization: shadow_organization, customer: shadow_customer, external_id: subscription.external_id)
    end

    it "creates the contract" do
      expect { result }.to change { shadow_organization.contracts.live.count }.by(1)
    end
  end

  context "when the plan is not mapped" do
    let(:other_plan) { create(:plan, organization:) }

    let(:subscription) do
      create(:subscription, organization:, customer:, plan: other_plan, started_at:, subscription_at:)
    end

    it "skips the subscription" do
      expect { result }.not_to change { shadow_organization.contracts.count }

      expect(result).to be_success
      expect(shadow_organization.customers.count).to eq(0)
    end
  end

  context "when the subscription belongs to another organization" do
    let(:other_organization) { create(:organization) }
    let(:other_plan) { create(:plan, organization: other_organization, code: plan.code) }
    let(:other_customer) { create(:customer, organization: other_organization) }

    let(:subscription) do
      create(:subscription, organization: other_organization, customer: other_customer, plan: other_plan, started_at:, subscription_at:)
    end

    it "skips the subscription" do
      expect { result }.not_to change { shadow_organization.contracts.count }

      expect(result).to be_success
      expect(shadow_organization.customers.count).to eq(0)
    end
  end

  context "when the subscription runs on an override of a mapped plan" do
    let(:override_plan) { create(:plan, organization:, code: plan.code, parent: plan) }

    let(:subscription) do
      create(:subscription, organization:, customer:, plan: override_plan, started_at:, subscription_at:)
    end

    before { allow(Rails.logger).to receive(:info) }

    it "skips the subscription and logs it" do
      expect { result }.not_to change { shadow_organization.contracts.count }

      expect(result).to be_success
      expect(shadow_organization.customers.count).to eq(0)
      expect(Rails.logger).to have_received(:info).with(
        a_string_including(
          "plan_override_not_supported",
          "subscription #{subscription.external_id}",
          "migration #{migration.id}"
        )
      )
    end
  end

  context "when the subscription is terminated" do
    let(:subscription) do
      create(:subscription, :terminated, organization:, customer:, plan:)
    end

    it "skips the subscription" do
      expect { result }.not_to change { shadow_organization.contracts.count }
    end
  end

  context "when the subscription already ended" do
    let(:ending_at) { 1.day.ago }

    it "skips the subscription" do
      expect { result }.not_to change { shadow_organization.contracts.count }
    end
  end

  context "when the subscription ends in the future" do
    let(:ending_at) { Time.zone.parse("2099-01-01 12:00:00.654321") }

    it "carries the end over to the contract" do
      expect(result.contract.ended_at).to eq(ending_at)
    end
  end

  context "when the migration is not shadowing" do
    let(:status) { "paused" }

    it "does nothing" do
      expect { result }.not_to change { shadow_organization.contracts.count }

      expect(result).to be_success
      expect(result.contract).to be_nil
      expect(shadow_organization.customers.count).to eq(0)
    end
  end

  context "with anniversary billing", :premium do
    let(:subscription) do
      create(:subscription, :anniversary, organization:, customer:, plan:, started_at:, subscription_at:)
    end

    it "anchors the contract on the subscription date in the customer timezone" do
      expect(result.contract).to have_attributes(
        billing_time: "anniversary",
        billing_anchor_date: Date.new(2025, 3, 14)
      )
      expect(result.contract.customer.applicable_timezone).to eq("America/Los_Angeles")
    end

    context "when the customer has no timezone and its billing entity has one" do
      let(:paris_entity) { create(:billing_entity, organization:, timezone: "Europe/Paris") }
      let(:shadow_entity_code) { paris_entity.code }
      let(:subscription_at) { Time.zone.parse("2025-03-14 23:30:00") }

      let(:customer) do
        create(:customer, organization:, billing_entity: paris_entity, timezone: nil)
      end

      it "uses the timezone of the billing entity for the shadow customer and the anchor" do
        expect(result.contract.customer.applicable_timezone).to eq("Europe/Paris")
        expect(result.contract.billing_anchor_date).to eq(Date.new(2025, 3, 15))
      end
    end
  end

  context "with calendar billing" do
    let(:subscription) do
      create(:subscription, :calendar, organization:, customer:, plan:, started_at:, subscription_at:)
    end

    it "anchors the contract on Jan 1 of the start year in the customer timezone" do
      expect(result.contract).to have_attributes(billing_time: "calendar", billing_anchor_date: Date.new(2025, 1, 1))
    end

    context "when the start is still the previous year in the customer timezone" do
      let(:started_at) { Time.zone.parse("2025-01-01 05:00:00") }

      it "anchors the contract on Jan 1 of that previous year" do
        expect(result.contract.billing_anchor_date).to eq(Date.new(2024, 1, 1)) # 2024-12-31 21:00 in Los Angeles
      end
    end

    context "with a weekly plan" do
      let(:plan) { create(:plan, organization:, interval: :weekly) }

      it "anchors the contract on the Monday of the start week" do
        expect(result.contract.billing_anchor_date).to eq(Date.new(2025, 2, 24)) # 2025-03-01 is a Saturday
      end
    end
  end

  context "when the customer is created concurrently" do
    let(:concurrent_customer) do
      create(:customer, organization: shadow_organization, external_id: customer.external_id)
    end

    before do
      allow(Customers::CreateService).to receive(:call) do
        concurrent_customer
        BaseService::Result.new.single_validation_failure!(field: :external_id, error_code: "value_already_exist")
      end
    end

    it "creates the contract for the customer created by the other writer" do
      expect(result).to be_success
      expect(result.contract.customer).to eq(concurrent_customer)
    end
  end

  context "when the contract is created concurrently" do
    before do
      allow(Rails.logger).to receive(:warn)
      allow(Contracts::CreateService).to receive(:call).and_return(
        BaseService::Result.new.single_validation_failure!(field: :external_id, error_code: "value_already_exists")
      )
    end

    it "skips it without logging a failure" do
      expect(result).to be_success
      expect(result.contract).to be_nil
      expect(Rails.logger).not_to have_received(:warn)
    end
  end

  context "when the contract is created concurrently with the same code" do
    before do
      allow(Rails.logger).to receive(:warn)
      allow(Contracts::CreateService).to receive(:call).and_return(
        BaseService::Result.new.single_validation_failure!(field: :code, error_code: "value_already_exist")
      )
    end

    it "skips it without logging a failure" do
      expect(result).to be_success
      expect(result.contract).to be_nil
      expect(Rails.logger).not_to have_received(:warn)
    end
  end

  context "when the contract cannot be created" do
    let(:migration) do
      create(
        :billing_engine_migration,
        organization:,
        shadow_organization:,
        plan_mapping: {plan.code => "missing_catalog_plan"}
      )
    end

    before { allow(Rails.logger).to receive(:warn) }

    it "logs the failure and returns it" do
      expect(result).to be_failure
      expect(result.contract).to be_nil

      expect(Rails.logger).to have_received(:warn).with(
        a_string_including(
          "cannot create contract",
          "subscription #{subscription.external_id}",
          "migration #{migration.id}"
        )
      )
    end
  end

  context "when the shadow organization has no billing entity with the code of the customer" do
    let(:shadow_entity_code) { "unknown_entity" }

    before { allow(Rails.logger).to receive(:warn) }

    it "logs the failure, returns it and creates nothing" do
      expect { result }
        .to not_change { shadow_organization.customers.count }
        .and not_change { shadow_organization.contracts.count }

      expect(result).to be_failure
      expect(Rails.logger).to have_received(:warn).with(
        a_string_including("cannot create customer", "subscription #{subscription.external_id}")
      )
    end
  end
end

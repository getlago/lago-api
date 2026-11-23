# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::CopySubscriptionService do
  subject(:result) { described_class.call(migration:, subscription:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:shadow_organization) { create(:shadow_organization) }
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
  let(:plan_mapping) { {plan.code => catalog_plan.code} }

  let(:migration) do
    create(
      :billing_engine_migration,
      organization:,
      shadow_organization:,
      status:,
      plan_mapping:
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

  before { create(:billing_entity, organization: shadow_organization, code: shadow_entity_code, email_settings: []) }

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

  context "when the subscription already has a live contract" do
    before do
      shadow_customer = create(:customer, organization: shadow_organization, external_id: customer.external_id)
      create(
        :contract,
        :pending,
        organization: shadow_organization,
        customer: shadow_customer,
        external_id: subscription.external_id,
        code: subscription.id
      )
    end

    it "does not create another one" do
      expect { result }.not_to change { shadow_organization.contracts.count }

      expect(result).to be_success
      expect(result.contract).to be_nil
    end
  end

  context "when a live contract of another subscription has the subscription external id" do
    before do
      allow(Rails.logger).to receive(:info)
      create(
        :contract,
        customer: create(:customer, organization: shadow_organization),
        external_id: subscription.external_id,
        code: "other-subscription-id"
      )
    end

    it "skips the subscription and logs it" do
      expect { result }
        .to not_change { shadow_organization.contracts.count }
        .and not_change { shadow_organization.customers.count }

      expect(result).to be_success
      expect(result.contract).to be_nil
      expect(Rails.logger).to have_received(:info).with(
        a_string_including(
          "external_id_taken_by_other_subscription",
          "subscription #{subscription.external_id}",
          "migration #{migration.id}"
        )
      )
    end
  end

  context "when the shadow contract of this subscription has ended" do
    before do
      allow(Rails.logger).to receive(:info)
      create(
        :contract,
        :terminated,
        customer: create(:customer, organization: shadow_organization),
        external_id: subscription.external_id,
        code: subscription.id
      )
    end

    it "skips the subscription and logs it" do
      expect { result }.not_to change { shadow_organization.contracts.count }

      expect(result).to be_success
      expect(result.contract).to be_nil
      expect(Rails.logger).to have_received(:info).with(a_string_including("shadow_contract_ended"))
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
      expect(result.contract.billing_anchor_date).to eq(Date.new(2025, 3, 14))
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
      expect(result.contract.billing_anchor_date).to eq(Date.new(2025, 1, 1))
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
      allow(Contracts::CreateService).to receive(:call) do
        create_concurrent_contract(code: subscription.id)
        BaseService::Result.new.single_validation_failure!(field: :external_id, error_code: "value_already_exists")
      end
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
      allow(Contracts::CreateService).to receive(:call) do
        create_concurrent_contract(code: subscription.id)
        BaseService::Result.new.single_validation_failure!(field: :code, error_code: "value_already_exist")
      end
    end

    it "skips it without logging a failure" do
      expect(result).to be_success
      expect(result.contract).to be_nil
      expect(Rails.logger).not_to have_received(:warn)
    end
  end

  context "when another subscription takes the external id concurrently" do
    before do
      allow(Rails.logger).to receive(:info)
      allow(Contracts::CreateService).to receive(:call) do
        create_concurrent_contract(code: "other-subscription-id")
        BaseService::Result.new.single_validation_failure!(field: :external_id, error_code: "value_already_exists")
      end
    end

    it "skips the subscription and logs it" do
      expect(result).to be_success
      expect(Rails.logger).to have_received(:info).with(a_string_including("external_id_taken_by_other_subscription"))
    end
  end

  context "when a uniqueness conflict leaves no contract to explain it" do
    before do
      allow(Rails.logger).to receive(:warn)
      allow(Contracts::CreateService).to receive(:call).and_return(
        BaseService::Result.new.single_validation_failure!(field: :code, error_code: "value_already_exist")
      )
    end

    it "logs the failure and returns it" do
      expect(result).to be_failure
      expect(Rails.logger).to have_received(:warn).with(a_string_including("cannot create contract"))
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

  context "when the shadow organization has a webhook endpoint" do
    before do
      allow(Rails.logger).to receive(:warn)
      create(:webhook_endpoint, organization: shadow_organization)
    end

    it "logs the failure, returns it and creates nothing" do
      expect { result }
        .to not_change { shadow_organization.customers.count }
        .and not_change { shadow_organization.contracts.count }

      expect(result).to be_failure
      expect(result.error.code).to eq("shadow_organization_not_isolated")
      expect(Rails.logger).to have_received(:warn).with(
        a_string_including("cannot create customer", "subscription #{subscription.external_id}")
      )
    end
  end

  context "when the shadow organization has no billing entity with the code of the customer" do
    let(:shadow_entity_code) { "unknown_entity" }
    let(:other_customer) { create(:customer, organization:, billing_entity: create(:billing_entity, organization:)) }
    let(:subscription) { create(:subscription, organization:, customer: other_customer, plan:, started_at:, subscription_at:) }

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

  context "when the subscription is terminated with a live shadow contract" do
    let(:terminated_at) { 1.hour.ago.change(usec: 0) }
    let(:subscription) { create(:subscription, :terminated, organization:, customer:, plan:, terminated_at:) }
    let(:contract) { create_shadow_contract(code: subscription.id) }

    before { contract }

    it "terminates the contract when the subscription was terminated" do
      expect(result).to be_success
      expect(contract.reload).to have_attributes(status: "terminated", terminated_at:)
    end

    context "when the contract was terminated concurrently" do
      before do
        allow(Contracts::TerminateService).to receive(:call).and_return(
          BaseService::Result.new.single_validation_failure!(field: :contract, error_code: "cannot_terminate")
        )
      end

      it "succeeds" do
        expect(result).to be_success
      end
    end

    context "when the contract cannot be terminated" do
      before do
        allow(Rails.logger).to receive(:warn)
        allow(Contracts::TerminateService).to receive(:call).and_return(
          BaseService::Result.new.lock_acquisition_failure!(message: "locked")
        )
      end

      it "logs the failure and returns it" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::LockAcquisitionFailure)
        expect(Rails.logger).to have_received(:warn).with(
          a_string_including("cannot terminate contract #{subscription.id}", "subscription #{subscription.external_id}")
        )
      end
    end
  end

  context "when the subscription was loaded as active before its termination committed" do
    let(:terminated_at) { 1.hour.ago.change(usec: 0) }

    before { Subscription.find(subscription.id).update!(status: :terminated, terminated_at:) }

    it "does not create a contract from the stale copy" do
      expect { result }.not_to change { shadow_organization.contracts.count }

      expect(result).to be_success
      expect(subscription).to be_terminated
    end

    context "when the subscription already has a live shadow contract" do
      let(:contract) { create_shadow_contract(code: subscription.id) }

      before { contract }

      it "terminates the contract" do
        expect(result).to be_success
        expect(contract.reload).to have_attributes(status: "terminated", terminated_at:)
      end
    end
  end

  context "when the copy runs" do
    let(:previous_subscription) do
      create(:subscription, :terminated, organization:, customer:, plan:, external_id: subscription.external_id)
    end

    it "writes the contract while holding the copy lock of every subscription of the external id" do
      previous_copy_lock = BillingEngineMigrations::SubscriptionCopyLockService.new(subscription: previous_subscription)
      allow(Contracts::CreateService).to receive(:call).and_wrap_original do |original, **args|
        expect(previous_copy_lock).to be_locked
        original.call(**args)
      end

      expect(result).to be_success
      expect(Contracts::CreateService).to have_received(:call)
      expect(previous_copy_lock).not_to be_locked
    end
  end

  context "when a live contract with the external id has the id of a terminated subscription of another organization" do
    let(:foreign_subscription) { create(:subscription, :terminated) }
    let(:contract) { create_shadow_contract(code: foreign_subscription.id) }

    before do
      contract
      allow(Rails.logger).to receive(:info)
    end

    it "leaves the contract live and skips the subscription" do
      expect(result).to be_success
      expect(contract.reload.status).to eq("active")
      expect(Rails.logger).to have_received(:info).with(a_string_including("external_id_taken_by_other_subscription"))
    end
  end

  context "when the subscription is terminated and its shadow contract already ended" do
    let(:subscription) { create(:subscription, :terminated, organization:, customer:, plan:) }

    before { create_shadow_contract(code: subscription.id, status: :terminated, terminated_at: Time.current) }

    it "does nothing" do
      allow(Contracts::TerminateService).to receive(:call)

      expect(result).to be_success
      expect(Contracts::TerminateService).not_to have_received(:call)
    end
  end

  context "when a pending subscription is canceled with a pending shadow contract" do
    let(:subscription) { create(:subscription, :canceled, organization:, customer:, plan:) }
    let(:contract) { create_shadow_contract(code: subscription.id, status: :pending, started_at: 1.day.from_now) }

    before { contract }

    it "cancels the contract" do
      expect(result).to be_success
      expect(contract.reload.status).to eq("canceled")
    end
  end

  context "when the plan of an active subscription is no longer mapped" do
    let(:plan_mapping) { {"other_plan" => catalog_plan.code} }
    let(:contract) { create_shadow_contract(code: subscription.id) }

    before { contract }

    it "terminates its shadow contract" do
      freeze_time do
        expect(result).to be_success
        expect(contract.reload).to have_attributes(status: "terminated", terminated_at: Time.current)
      end
    end
  end

  context "when the subscription replaces a terminated one with the same external id" do
    let(:terminated_at) { 1.hour.ago.change(usec: 0) }
    let(:previous_subscription) do
      create(
        :subscription,
        :terminated,
        organization:,
        customer:,
        plan: previous_plan,
        external_id: subscription.external_id,
        terminated_at:
      )
    end
    let(:previous_plan) { create(:plan, organization:) }
    let(:previous_contract) { create_shadow_contract(code: previous_subscription.id) }

    before { previous_contract }

    it "terminates the previous contract and creates the new one" do
      expect(result).to be_success
      expect(previous_contract.reload).to have_attributes(status: "terminated", terminated_at:)
      expect(shadow_organization.contracts.live.where(external_id: subscription.external_id))
        .to contain_exactly(have_attributes(code: subscription.id, catalog_plan:))
    end

    context "when the new subscription runs on an override of a mapped plan" do
      let(:override_plan) { create(:plan, organization:, code: plan.code, parent: plan) }
      let(:subscription) { create(:subscription, organization:, customer:, plan: override_plan, started_at:, subscription_at:) }

      before { allow(Rails.logger).to receive(:info) }

      it "terminates the previous contract without creating one" do
        expect(result).to be_success
        expect(previous_contract.reload.status).to eq("terminated")
        expect(shadow_organization.contracts.live.where(external_id: subscription.external_id)).to be_empty
        expect(Rails.logger).to have_received(:info).with(a_string_including("plan_override_not_supported"))
      end
    end

    context "when the previous subscription was canceled before it started" do
      let(:previous_subscription) do
        create(:subscription, :canceled, organization:, customer:, plan: previous_plan, external_id: subscription.external_id)
      end

      it "terminates the previous contract now" do
        freeze_time do
          expect(result).to be_success
          expect(previous_subscription.terminated_at).to be_nil
          expect(previous_contract.reload).to have_attributes(status: "terminated", terminated_at: Time.current)
        end
      end
    end

    context "when the previous contract cannot be terminated" do
      before do
        allow(Rails.logger).to receive(:warn)
        allow(Contracts::TerminateService).to receive(:call).and_return(
          BaseService::Result.new.lock_acquisition_failure!(message: "locked")
        )
      end

      it "returns the failure without creating the new contract" do
        expect { result }.not_to change { shadow_organization.contracts.count }

        expect(result).to be_failure
        expect(Rails.logger).to have_received(:warn).with(a_string_including("cannot terminate contract #{previous_subscription.id}"))
      end
    end
  end

  context "when the subscription end date changes after it was copied" do
    let(:ending_at) { Time.zone.parse("2099-01-01 12:00:00.654321") }
    let(:contract_ended_at) { nil }
    let(:contract) { create_shadow_contract(code: subscription.id, ended_at: contract_ended_at) }

    before do
      contract
      allow(Contracts::UpdateService).to receive(:call).and_call_original
    end

    it "moves the end date of the contract" do
      expect(result).to be_success
      expect(result.contract).to eq(contract)
      expect(contract.reload.ended_at).to eq(ending_at)
    end

    context "when the subscription end date is removed" do
      let(:ending_at) { nil }
      let(:contract_ended_at) { Time.zone.parse("2099-01-01 12:00:00") }

      it "removes the end date of the contract" do
        expect(result).to be_success
        expect(contract.reload.ended_at).to be_nil
      end
    end

    context "when the contract already has the end date" do
      let(:contract_ended_at) { ending_at }

      it "does not update the contract" do
        expect(result).to be_success
        expect(Contracts::UpdateService).not_to have_received(:call)
      end
    end

    context "when the subscription moved to an override of its plan" do
      let(:override_plan) { create(:plan, organization:, code: plan.code, parent: plan) }

      before { subscription.update!(plan: override_plan) }

      it "still moves the end date of the contract" do
        expect(result).to be_success
        expect(contract.reload.ended_at).to eq(ending_at)
      end
    end

    context "when the contract cannot be updated" do
      before do
        allow(Rails.logger).to receive(:warn)
        allow(Contracts::UpdateService).to receive(:call).and_return(
          BaseService::Result.new.single_validation_failure!(field: :contract, error_code: "contract_locked")
        )
      end

      it "logs the failure and returns it" do
        expect(result).to be_failure
        expect(Rails.logger).to have_received(:warn).with(a_string_including("cannot update contract"))
      end
    end
  end

  def create_shadow_contract(code:, started_at: 1.month.ago, **attributes)
    shadow_customer = shadow_organization.customers.find_by(external_id: customer.external_id) ||
      create(:customer, organization: shadow_organization, external_id: customer.external_id)

    create(
      :contract,
      organization: shadow_organization,
      customer: shadow_customer,
      external_id: subscription.external_id,
      code:,
      started_at:,
      **attributes
    )
  end

  def create_concurrent_contract(code:)
    create(
      :contract,
      customer: create(:customer, organization: shadow_organization),
      external_id: subscription.external_id,
      code:
    )
  end
end

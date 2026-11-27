# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::CopySubscriptionAlertsService, :premium do
  subject(:result) { described_class.call(migration:, subscription:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:subscription) { create(:subscription, organization:) }
  let_it_be(:billable_metric) { create(:billable_metric, organization:) }

  let(:status) { "shadowing" }
  let(:shadow_feature_flags) { %w[product_catalog contract_alerts] }
  let(:shadow_organization) { create(:shadow_organization, feature_flags: shadow_feature_flags) }
  let(:migration) { create(:billing_engine_migration, organization:, shadow_organization:, status:) }

  let(:contract_external_id) { subscription.external_id }
  let(:contract_status) { :active }
  let(:contract) do
    create(
      :contract,
      customer: create(:customer, organization: shadow_organization),
      external_id: contract_external_id,
      status: contract_status
    )
  end

  let(:shadow_metric) { create(:billable_metric, organization: shadow_organization, code: billable_metric.code) }
  let(:product) { create(:product, organization: shadow_organization, billable_metric: shadow_metric) }

  def price_on(contract, product)
    rate_card = create(:rate_card, organization: contract.organization, product:)
    create(:contract_rate_card, organization: contract.organization, contract:, rate_card:)
  end

  def create_v1_alert(factory, **attributes)
    create(factory, organization:, subscription_external_id: subscription.external_id, **attributes)
  end

  def copied_thresholds(contract_alert)
    contract_alert.thresholds.order(:value).pluck(:code, :value, :recurring, :notify_on)
  end

  before do
    price_on(contract, product)
    allow(Rails.logger).to receive(:info)
  end

  context "with a current usage amount alert" do
    let(:alert) do
      create_v1_alert(:usage_current_amount_alert, code: "spend", name: "Spend", thresholds: [10_00], recurring_threshold: 5_00)
    end

    before do
      alert
      create(:alert_threshold, alert:, code: "high", value: 20_00.5, notify_on: %w[triggered resolved])
    end

    it "copies it as a usage amount alert on the whole contract" do
      expect { result }.to change { shadow_organization.contract_alerts.count }.by(1)

      expect(result).to be_success
      contract_alert = contract.contract_alerts.sole
      expect(contract_alert).to be_a(UsageMonitoring::ContractUsageAmountAlert)
      expect(contract_alert).to have_attributes(
        alert_type: "usage_amount",
        code: "spend",
        name: "Spend",
        product: nil,
        product_filter: nil,
        with_product_filters: false
      )
      expect(copied_thresholds(contract_alert)).to eq([
        ["rec", 5_00, true, %w[triggered]],
        ["warn1000", 10_00, false, %w[triggered]],
        ["high", BigDecimal("2000.5"), false, %w[triggered resolved]]
      ])
    end

    it "passes the threshold values as plain decimal strings" do
      allow(UsageMonitoring::ContractAlerts::CreateService).to receive(:call).and_call_original

      expect(result).to be_success
      expect(UsageMonitoring::ContractAlerts::CreateService).to have_received(:call).with(
        organization: shadow_organization,
        contract:,
        params: hash_including(
          thresholds: contain_exactly(
            hash_including(code: "rec", value: "500.0"),
            hash_including(code: "warn1000", value: "1000.0"),
            hash_including(code: "high", value: "2000.5")
          )
        )
      )
    end

    it "copies it once when it runs twice" do
      described_class.call(migration:, subscription:)
      allow(UsageMonitoring::ContractAlerts::CreateService).to receive(:call).and_call_original

      expect { result }.not_to change { shadow_organization.contract_alerts.count }
      expect(result).to be_success
      expect(UsageMonitoring::ContractAlerts::CreateService).not_to have_received(:call)
      expect(contract.contract_alerts.pluck(:code)).to eq(["spend"])
    end
  end

  {
    billable_metric_current_usage_amount_alert: [UsageMonitoring::ContractUsageAmountAlert, "usage_amount"],
    billable_metric_current_usage_units_alert: [UsageMonitoring::ContractUsageUnitsAlert, "usage_units"]
  }.each do |factory, (contract_alert_class, alert_type)|
    context "with a #{factory.to_s.delete_suffix("_alert").tr("_", " ")} alert" do
      before { create_v1_alert(factory, billable_metric:, code: "tokens", name: "Tokens", thresholds: [1_000]) }

      it "copies it as a #{alert_type} alert on the shadow product of the metric and its filters" do
        expect(result).to be_success

        contract_alert = contract.contract_alerts.sole
        expect(contract_alert).to be_a(contract_alert_class)
        expect(contract_alert).to have_attributes(
          alert_type:,
          code: "tokens",
          name: "Tokens",
          product:,
          product_filter: nil,
          with_product_filters: true
        )
        expect(copied_thresholds(contract_alert)).to eq([["warn1000", 1_000, false, %w[triggered]]])
      end
    end
  end

  %i[lifetime_usage_amount_alert billable_metric_lifetime_usage_units_alert].each do |factory|
    context "with a #{factory} alert" do
      before do
        attributes = (factory == :billable_metric_lifetime_usage_units_alert) ? {billable_metric:} : {}
        create_v1_alert(factory, code: "lifetime", **attributes)
      end

      it "skips it with the reason" do
        expect(result).to be_success
        expect(contract.contract_alerts).to be_empty
        expect(Rails.logger).to have_received(:info).with(a_string_including("skipped alert lifetime: unsupported_alert_type"))
      end
    end
  end

  context "with a metric alert" do
    before { create_v1_alert(:billable_metric_current_usage_units_alert, billable_metric: alert_metric, code: "tokens") }

    let(:alert_metric) { billable_metric }

    context "with a second metric alert on another metric" do
      let(:calls_metric) { create(:billable_metric, organization:) }

      before { create_v1_alert(:billable_metric_current_usage_amount_alert, billable_metric: calls_metric, code: "calls") }

      it "copies the alert whose metric is priced and skips the other" do
        expect(result).to be_success
        expect(contract.contract_alerts.sole).to have_attributes(code: "tokens", product:)
        expect(Rails.logger).to have_received(:info).with(a_string_including("skipped alert calls: shadow_product_not_found"))
      end

      context "when the contract also prices a product of the second metric" do
        let(:calls_product) do
          create(
            :product,
            organization: shadow_organization,
            billable_metric: create(:billable_metric, organization: shadow_organization, code: calls_metric.code)
          )
        end

        before { price_on(contract, calls_product) }

        it "copies each alert on the product of its own metric" do
          expect(result).to be_success
          expect(contract.contract_alerts.order(:code).map { [it.code, it.product] })
            .to eq([["calls", calls_product], ["tokens", product]])
        end
      end
    end

    context "when no shadow product has the metric code" do
      let(:alert_metric) { create(:billable_metric, organization:) }

      it "skips it with the reason" do
        expect(result).to be_success
        expect(contract.contract_alerts).to be_empty
        expect(Rails.logger).to have_received(:info).with(a_string_including("skipped alert tokens: shadow_product_not_found"))
      end
    end

    context "when the shadow product is priced only on the contract of another external id" do
      let(:other_metric) { create(:billable_metric, organization:) }
      let(:alert_metric) { other_metric }

      before do
        other_shadow_metric = create(:billable_metric, organization: shadow_organization, code: other_metric.code)
        other_contract = create(:contract, customer: contract.customer)
        price_on(other_contract, create(:product, organization: shadow_organization, billable_metric: other_shadow_metric))
      end

      it "skips it with the reason" do
        expect(result).to be_success
        expect(contract.contract_alerts).to be_empty
        expect(Rails.logger).to have_received(:info).with(a_string_including("skipped alert tokens: shadow_product_not_found"))
      end
    end

    context "when the shadow product is priced only on a terminated contract of the external id" do
      let(:other_metric) { create(:billable_metric, organization:) }
      let(:alert_metric) { other_metric }

      before do
        other_shadow_metric = create(:billable_metric, organization: shadow_organization, code: other_metric.code)
        terminated_contract = create(:contract, :terminated, customer: contract.customer, external_id: contract.external_id)
        price_on(terminated_contract, create(:product, organization: shadow_organization, billable_metric: other_shadow_metric))
      end

      it "skips it with the reason" do
        expect { result }.not_to change { shadow_organization.contract_alerts.count }

        expect(result).to be_success
        expect(contract.contract_alerts).to be_empty
        expect(Rails.logger).to have_received(:info).with(a_string_including("skipped alert tokens: shadow_product_not_found"))
      end
    end

    context "when the shadow product with the metric code is not metered" do
      let(:other_metric) { create(:billable_metric, organization:) }
      let(:alert_metric) { other_metric }

      before do
        other_shadow_metric = create(:billable_metric, organization: shadow_organization, code: other_metric.code)
        fixed_product = create(:product, organization: shadow_organization, billable_metric: other_shadow_metric)
        fixed_product.update_column(:product_type, "fixed") # rubocop:disable Rails/SkipsModelValidations
        price_on(contract, fixed_product)
      end

      it "skips it with the reason" do
        expect(result).to be_success
        expect(contract.contract_alerts).to be_empty
        expect(Rails.logger).to have_received(:info).with(a_string_including("skipped alert tokens: shadow_product_not_found"))
      end
    end

    context "when two shadow products priced on the contract have the metric code" do
      before { price_on(contract, create(:product, organization: shadow_organization, billable_metric: shadow_metric)) }

      it "skips it with the reason" do
        expect(result).to be_success
        expect(contract.contract_alerts).to be_empty
        expect(Rails.logger).to have_received(:info).with(a_string_including("skipped alert tokens: shadow_product_ambiguous"))
      end
    end
  end

  context "with thresholds the contract alert refuses" do
    before { create_v1_alert(:usage_current_amount_alert, code: "spend", thresholds: [10_00, 10_00]) }

    it "skips the alert with the reason" do
      expect(result).to be_success
      expect(contract.contract_alerts).to be_empty
      expect(Rails.logger).to have_received(:info)
        .with(a_string_including("skipped alert spend: Validation errors:").and(a_string_including("duplicate_threshold_values")))
    end
  end

  context "when the shadow organization has no contract_alerts flag" do
    let(:shadow_feature_flags) { %w[product_catalog] }
    let(:stale_copy) { create(:contract_alert, organization: shadow_organization, contract_external_id: contract.external_id, code: "gone") }

    before do
      create_v1_alert(:usage_current_amount_alert, code: "spend")
      stale_copy
      allow(Rails.logger).to receive(:warn)
      allow(BillingEngineMigrations::SubscriptionCopyLockService).to receive(:call).and_call_original
    end

    it "skips the whole run with a warning, without taking the lock or touching the copies" do
      expect(result).to be_success
      expect(contract.contract_alerts).to eq([stale_copy])
      expect(BillingEngineMigrations::SubscriptionCopyLockService).not_to have_received(:call)
      expect(Rails.logger).to have_received(:warn).with(a_string_including("skipped: contract_alerts_unavailable"))
    end
  end

  context "without a premium license", premium: false do
    before do
      create_v1_alert(:usage_current_amount_alert, code: "spend")
      allow(Rails.logger).to receive(:warn)
    end

    it "skips the whole run with a warning" do
      expect(result).to be_success
      expect(contract.contract_alerts).to be_empty
      expect(Rails.logger).to have_received(:warn).with(a_string_including("skipped: contract_alerts_unavailable"))
    end
  end

  context "when the contract alert service cannot find the product" do
    before do
      create_v1_alert(:usage_current_amount_alert, code: "spend")
      allow(UsageMonitoring::ContractAlerts::CreateService).to receive(:call)
        .and_return(BaseService::Result.new.not_found_failure!(resource: "product"))
    end

    it "skips the alert with the reason" do
      expect(result).to be_success
      expect(Rails.logger).to have_received(:info).with(a_string_including("skipped alert spend: product_not_found"))
    end
  end

  context "with a metric alert copied on its shadow product" do
    before { create_v1_alert(:billable_metric_current_usage_units_alert, billable_metric:, code: "tokens") }

    it "targets the product by its code in the scope" do
      allow(UsageMonitoring::ContractAlerts::CreateService).to receive(:call).and_call_original

      expect(result).to be_success
      expect(UsageMonitoring::ContractAlerts::CreateService).to have_received(:call).with(
        organization: shadow_organization,
        contract:,
        params: hash_including(scope: [{type: "contract", product_code: product.code, with_product_filters: true}])
      )
    end
  end

  {
    "scope" => :scope,
    "a scope entry" => BaseService::ValidationFailure.item_field(:scope, 0, :product_code),
    "the alert type" => :alert_type
  }.each do |label, field|
    context "when the contract alert service refuses #{label} the copy built" do
      before do
        create_v1_alert(:usage_current_amount_alert, code: "first")
        create_v1_alert(:billable_metric_current_usage_amount_alert, billable_metric:, code: "second")
        allow(Rails.logger).to receive(:warn)
        allow(UsageMonitoring::ContractAlerts::CreateService).to receive(:call)
          .and_return(BaseService::Result.new.single_validation_failure!(field:, error_code: "value_is_mandatory"))
      end

      it "fails without copying the next alerts" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(UsageMonitoring::ContractAlerts::CreateService).to have_received(:call).once
        expect(Rails.logger).to have_received(:warn).with(a_string_including("cannot create alert first: Validation errors:"))
      end
    end
  end

  context "when the contract alert service fails unexpectedly" do
    before do
      create_v1_alert(:usage_current_amount_alert, code: "first")
      create_v1_alert(:billable_metric_current_usage_amount_alert, billable_metric:, code: "second")
      allow(Rails.logger).to receive(:warn)
      allow(UsageMonitoring::ContractAlerts::CreateService).to receive(:call)
        .and_return(BaseService::Result.new.service_failure!(code: "unexpected", message: "boom"))
    end

    it "fails without copying the next alerts" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ServiceFailure)
      expect(UsageMonitoring::ContractAlerts::CreateService).to have_received(:call).once
      expect(Rails.logger).to have_received(:warn).with(a_string_including("cannot create alert first: unexpected: boom"))
    end
  end

  context "with a terminated contract" do
    let(:contract_status) { :terminated }

    before { create_v1_alert(:usage_current_amount_alert, code: "spend") }

    it "skips the subscription" do
      expect(result).to be_success
      expect(shadow_organization.contract_alerts).to be_empty
      expect(Rails.logger).to have_received(:info).with(
        "BillingEngineMigrations::CopySubscriptionAlertsService: subscription #{subscription.external_id} " \
        "(migration #{migration.id}): skipped: contract_not_found"
      )
    end
  end

  context "with a newer terminated contract of the external id" do
    before do
      create(:contract, :terminated, customer: contract.customer, external_id: contract.external_id, created_at: contract.created_at + 1.day)
      create_v1_alert(:usage_current_amount_alert, code: "spend")
      allow(UsageMonitoring::ContractAlerts::CreateService).to receive(:call).and_call_original
    end

    it "copies the alert on the live contract" do
      expect(result).to be_success
      expect(UsageMonitoring::ContractAlerts::CreateService).to have_received(:call).with(hash_including(contract:))
      expect(shadow_organization.contract_alerts.pluck(:code)).to eq(["spend"])
    end
  end

  context "with a newer pending contract of the external id" do
    let(:pending_contract) do
      create(:contract, :pending, customer: contract.customer, external_id: contract.external_id, created_at: contract.created_at + 1.day)
    end

    before do
      pending_contract
      create_v1_alert(:usage_current_amount_alert, code: "spend")
      allow(UsageMonitoring::ContractAlerts::CreateService).to receive(:call).and_call_original
    end

    it "copies the alert on the newest live contract" do
      expect(result).to be_success
      expect(UsageMonitoring::ContractAlerts::CreateService).to have_received(:call).with(hash_including(contract: pending_contract))
      expect(shadow_organization.contract_alerts.pluck(:code)).to eq(["spend"])
    end
  end

  context "with a metric alert and a newer pending contract that prices nothing" do
    let(:pending_contract) do
      create(:contract, :pending, customer: contract.customer, external_id: contract.external_id, created_at: contract.created_at + 1.day)
    end

    before do
      pending_contract
      create_v1_alert(:billable_metric_current_usage_units_alert, billable_metric:, code: "tokens")
      allow(UsageMonitoring::ContractAlerts::CreateService).to receive(:call).and_call_original
    end

    it "copies it on the pending contract with the product priced on the active one" do
      expect(result).to be_success
      expect(UsageMonitoring::ContractAlerts::CreateService).to have_received(:call).with(hash_including(contract: pending_contract))
      expect(shadow_organization.contract_alerts.sole).to have_attributes(code: "tokens", product:, with_product_filters: true)
    end
  end

  context "when called with the terminated previous subscription of the external id" do
    subject(:result) { described_class.call(migration:, subscription: previous_subscription) }

    let(:previous_subscription) do
      create(:subscription, :terminated, organization:, customer: subscription.customer, external_id: subscription.external_id)
    end

    before { create_v1_alert(:usage_current_amount_alert, code: "spend") }

    it "reconciles the external id as the current subscription would" do
      expect(result).to be_success
      expect(contract.contract_alerts.pluck(:code)).to eq(["spend"])
    end
  end

  context "without a contract of the external id" do
    let(:contract_external_id) { SecureRandom.uuid }

    before { create_v1_alert(:usage_current_amount_alert, code: "spend") }

    it "skips the subscription" do
      expect(result).to be_success
      expect(shadow_organization.contract_alerts).to be_empty
      expect(Rails.logger).to have_received(:info).with(a_string_including("skipped: contract_not_found"))
    end
  end

  context "without a V1 alert" do
    let(:contract_external_id) { SecureRandom.uuid }

    it "does nothing" do
      expect(result).to be_success
      expect(shadow_organization.contract_alerts).to be_empty
      expect(Rails.logger).not_to have_received(:info)
    end
  end

  context "with a discarded V1 alert" do
    before { create_v1_alert(:usage_current_amount_alert, code: "spend").discard! }

    it "does not copy it" do
      expect(result).to be_success
      expect(shadow_organization.contract_alerts).to be_empty
    end
  end

  %w[paused aborted].each do |migration_status|
    context "when the migration is #{migration_status}" do
      let(:status) { migration_status }

      before { create_v1_alert(:usage_current_amount_alert, code: "spend") }

      it "copies nothing" do
        expect(result).to be_success
        expect(shadow_organization.contract_alerts).to be_empty
      end
    end
  end

  context "when the migration belongs to another organization" do
    let(:migration) { create(:billing_engine_migration, shadow_organization:) }

    before { create_v1_alert(:usage_current_amount_alert, code: "spend") }

    it "copies nothing" do
      expect(result).to be_success
      expect(shadow_organization.contract_alerts).to be_empty
    end
  end

  context "when the copy runs" do
    before { create_v1_alert(:usage_current_amount_alert, code: "spend") }

    it "writes the contract alerts while holding the copy lock of the external id" do
      copy_lock = BillingEngineMigrations::SubscriptionCopyLockService.new(subscription:)
      allow(UsageMonitoring::ContractAlerts::CreateService).to receive(:call).and_wrap_original do |original, **args|
        expect(copy_lock).to be_locked
        original.call(**args)
      end

      expect(result).to be_success
      expect(UsageMonitoring::ContractAlerts::CreateService).to have_received(:call)
      expect(copy_lock).not_to be_locked
    end
  end

  describe "reconciliation of the contract alerts of the external id" do
    let(:kept_codes) { shadow_organization.contract_alerts.where(contract_external_id: subscription.external_id).pluck(:code) }

    def copy_now
      described_class.call(migration:, subscription:)
    end

    def destroy_v1_alerts
      UsageMonitoring::Alerts::DestroyAllService.call(alertable: subscription)
    end

    def discarded?(contract_alert)
      UsageMonitoring::ContractAlert.with_discarded.find(contract_alert.id).discarded?
    end

    context "when the V1 alerts of the subscription are destroyed" do
      let(:other_external_id_alert) { create(:contract_alert, organization: shadow_organization) }
      let(:other_organization_alert) do
        create(:contract_alert, organization: create(:organization), contract_external_id: subscription.external_id)
      end

      before do
        create_v1_alert(:usage_current_amount_alert, code: "spend")
        create_v1_alert(:billable_metric_current_usage_units_alert, billable_metric:, code: "tokens")
        copy_now
        other_external_id_alert
        other_organization_alert
        destroy_v1_alerts
      end

      it "soft deletes every contract alert of the external id and creates none" do
        copies = contract.contract_alerts.order(:code).to_a
        allow(UsageMonitoring::ContractAlerts::CreateService).to receive(:call).and_call_original

        expect(copies.map(&:code)).to contain_exactly("spend", "tokens")
        expect(result).to be_success
        expect(contract.contract_alerts).to be_empty
        expect(UsageMonitoring::ContractAlert.with_discarded.where(id: copies.map(&:id)).pluck(:deleted_at)).to all(be_present)
        expect(UsageMonitoring::ContractAlertThreshold.where(contract_alert_id: copies.map(&:id))).to be_empty
        expect(UsageMonitoring::ContractAlerts::CreateService).not_to have_received(:call)
        expect(Rails.logger).to have_received(:info).with(a_string_including("destroyed alert spend: v1_alert_missing"))
        expect(Rails.logger).to have_received(:info).with(a_string_including("destroyed alert tokens: v1_alert_missing"))
      end

      it "leaves the contract alerts of another external id or another organization" do
        expect(result).to be_success
        expect(discarded?(other_external_id_alert)).to be(false)
        expect(discarded?(other_organization_alert)).to be(false)
      end
    end

    context "without a V1 alert and with a contract alert of the external id only in another organization" do
      let(:contract_status) { :terminated }

      before { create(:contract_alert, organization: create(:organization), contract_external_id: subscription.external_id) }

      it "does nothing" do
        expect(result).to be_success
        expect(Rails.logger).not_to have_received(:info)
      end
    end

    context "when a V1 alert is discarded and another one is created with a new code" do
      let(:old_alert) { create_v1_alert(:usage_current_amount_alert, code: "spend", name: "Spend") }
      let(:old_copy) { contract.contract_alerts.sole }

      before do
        old_alert
        copy_now
        old_copy
        old_alert.discard!
        create_v1_alert(:usage_current_amount_alert, code: "spend_v2", name: "Spend v2")
      end

      it "destroys the old copy before creating the new one" do
        expect(result).to be_success
        expect(discarded?(old_copy)).to be(true)
        expect(contract.contract_alerts.sole).to have_attributes(code: "spend_v2", name: "Spend v2", alert_type: "usage_amount")
      end
    end

    context "when a V1 alert is recreated with the same code and other values" do
      let(:other_metric) { create(:billable_metric, organization:) }
      let(:other_product) do
        create(:product, organization: shadow_organization, billable_metric: create(:billable_metric, organization: shadow_organization, code: other_metric.code))
      end
      let(:first_copy) { contract.contract_alerts.sole }

      def v1_alert_with(factory, thresholds:, **attributes)
        alert = create_v1_alert(factory, code: "spend", name: "Spend", thresholds: [], **attributes)
        thresholds.each { create(:alert_threshold, alert:, **it) }
        alert
      end

      def copy_then_recreate(from:, to:)
        v1_alert_with(from.fetch(:factory), thresholds: [{code: "high", value: 10_00}], **from.except(:factory))
        copy_now
        first_copy
        destroy_v1_alerts
        v1_alert_with(to.fetch(:factory), thresholds: to.fetch(:thresholds, [{code: "high", value: 10_00}]), **to.except(:factory, :thresholds))
      end

      def expect_replaced_copy(**attributes)
        expect(result).to be_success
        expect(discarded?(first_copy)).to be(true)
        expect(kept_codes).to eq(["spend"])
        copy = contract.contract_alerts.sole
        expect(copy).to have_attributes(code: "spend", **attributes)
        expect(Rails.logger).to have_received(:info).with(a_string_including("destroyed alert spend: content_differs"))
        copy
      end

      before { price_on(contract, other_product) }

      it "replaces the copy when only the alert type differs" do
        copy_then_recreate(
          from: {factory: :billable_metric_current_usage_amount_alert, billable_metric:},
          to: {factory: :billable_metric_current_usage_units_alert, billable_metric:}
        )

        expect_replaced_copy(alert_type: "usage_units", product:, with_product_filters: true)
      end

      it "replaces the copy when only the metric differs" do
        copy_then_recreate(
          from: {factory: :billable_metric_current_usage_amount_alert, billable_metric:},
          to: {factory: :billable_metric_current_usage_amount_alert, billable_metric: other_metric}
        )

        expect_replaced_copy(alert_type: "usage_amount", product: other_product, with_product_filters: true)
      end

      it "replaces a metric copy by a whole contract copy" do
        copy_then_recreate(
          from: {factory: :billable_metric_current_usage_amount_alert, billable_metric:},
          to: {factory: :usage_current_amount_alert}
        )

        expect_replaced_copy(alert_type: "usage_amount", product: nil, with_product_filters: false)
      end

      it "replaces the copy when only the name differs" do
        copy_then_recreate(
          from: {factory: :usage_current_amount_alert},
          to: {factory: :usage_current_amount_alert, name: "Spending"}
        )

        expect_replaced_copy(name: "Spending")
      end

      {
        "value" => {code: "high", value: 20_00},
        "code" => {code: "higher", value: 10_00},
        "recurring flag" => {code: "high", value: 10_00, recurring: true},
        "notify_on" => {code: "high", value: 10_00, notify_on: %w[triggered resolved]}
      }.each do |field, threshold|
        it "replaces the copy when only the threshold #{field} differs" do
          copy_then_recreate(
            from: {factory: :usage_current_amount_alert},
            to: {factory: :usage_current_amount_alert, thresholds: [threshold]}
          )

          copy = expect_replaced_copy
          expected = {recurring: false, notify_on: %w[triggered]}.merge(threshold)
          expect(copied_thresholds(copy)).to eq([expected.values_at(:code, :value, :recurring, :notify_on)])
        end
      end

      it "replaces the copy when a threshold is added" do
        copy_then_recreate(
          from: {factory: :usage_current_amount_alert},
          to: {factory: :usage_current_amount_alert, thresholds: [{code: "high", value: 10_00}, {code: "higher", value: 20_00}]}
        )

        copy = expect_replaced_copy
        expect(copy.thresholds.count).to eq(2)
      end

      it "leaves no copy when the new type is not copied" do
        copy_then_recreate(from: {factory: :usage_current_amount_alert}, to: {factory: :lifetime_usage_amount_alert})

        expect(result).to be_success
        expect(discarded?(first_copy)).to be(true)
        expect(kept_codes).to be_empty
        expect(Rails.logger).to have_received(:info).with(a_string_including("destroyed alert spend: unsupported_alert_type"))
        expect(Rails.logger).to have_received(:info).with(a_string_including("skipped alert spend: unsupported_alert_type")).once
      end

      it "leaves no copy when the new metric has no shadow product" do
        copy_then_recreate(
          from: {factory: :usage_current_amount_alert},
          to: {factory: :billable_metric_current_usage_amount_alert, billable_metric: create(:billable_metric, organization:)}
        )

        expect(result).to be_success
        expect(discarded?(first_copy)).to be(true)
        expect(kept_codes).to be_empty
        expect(Rails.logger).to have_received(:info).with(a_string_including("destroyed alert spend: shadow_product_not_found"))
        expect(Rails.logger).to have_received(:info).with(a_string_including("skipped alert spend: shadow_product_not_found")).once
      end

      it "leaves no copy when the contract alert refuses the new thresholds" do
        copy_then_recreate(
          from: {factory: :usage_current_amount_alert},
          to: {factory: :usage_current_amount_alert, thresholds: [{code: "a", value: 30_00}, {code: "b", value: 30_00}]}
        )

        expect(result).to be_success
        expect(discarded?(first_copy)).to be(true)
        expect(kept_codes).to be_empty
        expect(Rails.logger).to have_received(:info).with(a_string_including("skipped alert spend: Validation errors:"))
      end
    end

    context "when the copy of a metric alert was changed on the shadow side" do
      let(:first_copy) { contract.contract_alerts.sole }

      before do
        create_v1_alert(:billable_metric_current_usage_amount_alert, billable_metric:, code: "tokens")
        copy_now
      end

      it "replaces a copy without product filters" do
        first_copy.update_column(:with_product_filters, false) # rubocop:disable Rails/SkipsModelValidations

        expect(result).to be_success
        expect(discarded?(first_copy)).to be(true)
        expect(contract.contract_alerts.sole).to have_attributes(code: "tokens", product:, with_product_filters: true)
        expect(Rails.logger).to have_received(:info).with(a_string_including("destroyed alert tokens: content_differs"))
      end

      it "replaces a copy scoped to a product filter" do
        product_filter = create(:product_filter, organization: shadow_organization, product:)
        first_copy.update_column(:product_filter_id, product_filter.id) # rubocop:disable Rails/SkipsModelValidations

        expect(result).to be_success
        expect(discarded?(first_copy)).to be(true)
        expect(contract.contract_alerts.sole).to have_attributes(code: "tokens", product:, product_filter: nil, with_product_filters: true)
      end
    end

    context "when the copy matches its V1 alert" do
      let(:alert) { create_v1_alert(:usage_current_amount_alert, code: "spend", name: "Spend", thresholds: [10_00], recurring_threshold: 5_00) }

      before do
        create(:alert_threshold, alert:, code: "high", value: 20_00.5, notify_on: %w[resolved triggered])
        create(:alert_threshold, alert:, code: nil, value: 30_00)
        create(:alert_threshold, alert:, code: nil, value: 40_00)
        copy_now
        allow(UsageMonitoring::ContractAlerts::DestroyService).to receive(:call).and_call_original
        allow(UsageMonitoring::ContractAlerts::CreateService).to receive(:call).and_call_original
      end

      it "keeps it with the same id" do
        copy_id = contract.contract_alerts.sole.id

        expect(result).to be_success
        expect(contract.contract_alerts.sole.id).to eq(copy_id)
        expect(UsageMonitoring::ContractAlerts::DestroyService).not_to have_received(:call)
        expect(UsageMonitoring::ContractAlerts::CreateService).not_to have_received(:call)
      end
    end

    context "when the copy loads its thresholds in another order than its V1 alert" do
      let(:alert) { create_v1_alert(:usage_current_amount_alert, code: "spend", name: "Spend", thresholds: [10_00]) }
      let(:copy) { contract.contract_alerts.sole }

      before do
        create(:alert_threshold, alert:, code: "high", value: 20_00, notify_on: %w[resolved triggered])
        copy_now
        # Rewriting a row moves it after "high" in the table, so the copy's thresholds load in another order
        copy.thresholds.where.not(code: "high").sole.update!(updated_at: 1.minute.from_now)
        allow(UsageMonitoring::ContractAlerts::DestroyService).to receive(:call).and_call_original
      end

      it "keeps it with the same id" do
        copy_id = copy.id

        expect(result).to be_success
        expect(contract.contract_alerts.sole.id).to eq(copy_id)
        expect(UsageMonitoring::ContractAlerts::DestroyService).not_to have_received(:call)
      end
    end

    context "when a V1 threshold was stored before notify_on was normalized" do
      let(:alert) { create_v1_alert(:usage_current_amount_alert, code: "spend", name: "Spend", thresholds: [10_00]) }

      before do
        # Raw SQL: assigning the attribute would normalize the value
        alert.thresholds.update_all("notify_on = ARRAY['resolved', 'triggered']::varchar[]") # rubocop:disable Rails/SkipsModelValidations
        copy_now
        allow(UsageMonitoring::ContractAlerts::DestroyService).to receive(:call).and_call_original
      end

      it "keeps the copy with the same id" do
        copy_id = contract.contract_alerts.sole.id

        expect(alert.thresholds.pick(:notify_on)).to eq(%w[resolved triggered])
        expect(result).to be_success
        expect(contract.contract_alerts.sole.id).to eq(copy_id)
        expect(UsageMonitoring::ContractAlerts::DestroyService).not_to have_received(:call)
      end
    end

    context "when a plan move leaves the external id a new contract" do
      let(:new_contract) do
        create(:contract, customer: contract.customer, external_id: contract.external_id, created_at: contract.created_at + 1.day)
      end
      let(:new_contract_product) { create(:product, organization: shadow_organization, billable_metric: shadow_metric) }
      let(:first_copy) { contract.contract_alerts.sole }

      before do
        create_v1_alert(:billable_metric_current_usage_units_alert, billable_metric:, code: "tokens")
        copy_now
        first_copy
        contract.update!(status: :terminated, terminated_at: Time.current)
        price_on(new_contract, new_contract_product)
      end

      it "replaces the copy with one on the product the new contract prices for the metric" do
        expect(result).to be_success
        expect(discarded?(first_copy)).to be(true)
        expect(new_contract.contract_alerts.sole).to have_attributes(code: "tokens", product: new_contract_product)
      end

      context "when the new contract prices the same product" do
        let(:new_contract_product) { product }

        it "keeps the copy" do
          expect(result).to be_success
          expect(new_contract.contract_alerts.sole.id).to eq(first_copy.id)
        end
      end
    end

    context "when a V1 alert is created between two runs" do
      before do
        create_v1_alert(:usage_current_amount_alert, code: "spend")
        copy_now
      end

      it "copies the new alert and destroys nothing" do
        first_copy = contract.contract_alerts.sole
        create_v1_alert(:billable_metric_current_usage_units_alert, billable_metric:, code: "tokens")
        allow(UsageMonitoring::ContractAlerts::DestroyService).to receive(:call).and_call_original

        expect(result).to be_success
        expect(contract.contract_alerts.order(:code).pluck(:id, :code)).to match([[first_copy.id, "spend"], [be_present, "tokens"]])
        expect(UsageMonitoring::ContractAlerts::DestroyService).not_to have_received(:call)
      end
    end

    context "when the destroy of a stale copy fails" do
      before do
        create_v1_alert(:usage_current_amount_alert, code: "a_spend")
        create_v1_alert(:billable_metric_current_usage_units_alert, billable_metric:, code: "b_tokens")
        copy_now
        destroy_v1_alerts
        create_v1_alert(:usage_current_amount_alert, code: "c_new")
        allow(Rails.logger).to receive(:warn)
        allow(UsageMonitoring::ContractAlerts::DestroyService).to receive(:call)
          .and_return(BaseService::Result.new.service_failure!(code: "unexpected", message: "boom"))
        allow(UsageMonitoring::ContractAlerts::CreateService).to receive(:call).and_call_original
      end

      it "fails without destroying the next copies or creating any" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(UsageMonitoring::ContractAlerts::DestroyService).to have_received(:call).once
        expect(UsageMonitoring::ContractAlerts::CreateService).not_to have_received(:call)
        expect(Rails.logger).to have_received(:warn).with(a_string_including("cannot destroy alert a_spend: unexpected: boom"))
      end
    end

    context "without a live contract of the external id" do
      let(:contract_status) { :terminated }
      let(:contract_alert) { create(:contract_alert, organization: shadow_organization, contract_external_id: subscription.external_id) }

      before { contract_alert }

      it "keeps the existing contract alerts" do
        expect(result).to be_success
        expect(discarded?(contract_alert)).to be(false)
        expect(Rails.logger).to have_received(:info).with(a_string_including("skipped: contract_not_found"))
      end
    end

    context "when the migration is paused" do
      let(:status) { "paused" }
      let(:contract_alert) { create(:contract_alert, organization: shadow_organization, contract_external_id: subscription.external_id) }

      before { contract_alert }

      it "destroys nothing" do
        expect(result).to be_success
        expect(discarded?(contract_alert)).to be(false)
      end
    end

    context "when a stale copy is replaced" do
      before do
        create_v1_alert(:usage_current_amount_alert, code: "spend", name: "Spend")
        copy_now
        destroy_v1_alerts
        create_v1_alert(:usage_current_amount_alert, code: "spend", name: "Spending")
      end

      it "destroys and creates the contract alerts while holding the copy lock of the external id" do
        copy_lock = BillingEngineMigrations::SubscriptionCopyLockService.new(subscription:)
        [UsageMonitoring::ContractAlerts::DestroyService, UsageMonitoring::ContractAlerts::CreateService].each do |service|
          allow(service).to receive(:call).and_wrap_original do |original, **args|
            expect(copy_lock).to be_locked
            original.call(**args)
          end
        end

        expect(result).to be_success
        expect(UsageMonitoring::ContractAlerts::DestroyService).to have_received(:call)
        expect(UsageMonitoring::ContractAlerts::CreateService).to have_received(:call)
        expect(copy_lock).not_to be_locked
      end
    end
  end
end

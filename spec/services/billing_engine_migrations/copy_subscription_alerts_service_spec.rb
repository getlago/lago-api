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

    before { create_v1_alert(:usage_current_amount_alert, code: "spend") }

    it "skips the alert as forbidden" do
      expect(result).to be_success
      expect(contract.contract_alerts).to be_empty
      expect(Rails.logger).to have_received(:info).with(a_string_including("skipped alert spend: feature_unavailable"))
    end
  end

  context "without a premium license", premium: false do
    before { create_v1_alert(:usage_current_amount_alert, code: "spend") }

    it "skips the alert as forbidden" do
      expect(result).to be_success
      expect(contract.contract_alerts).to be_empty
      expect(Rails.logger).to have_received(:info).with(a_string_including("skipped alert spend: feature_unavailable"))
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
end

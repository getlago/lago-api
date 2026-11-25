# frozen_string_literal: true

module BillingEngineMigrations
  class CopySubscriptionAlertsService < BaseService
    Result = BaseResult

    EXPECTED_REFUSALS = [
      BaseService::ForbiddenFailure,
      BaseService::ValidationFailure,
      BaseService::NotFoundFailure
    ].freeze

    def initialize(migration:, subscription:)
      @migration = migration
      @subscription = subscription
      super
    end

    def call
      return result unless migration.shadowing? && subscription.organization_id == migration.organization_id

      if contract_alerts_available?
        SubscriptionCopyLockService.call(subscription:) { copy_alerts }
      else
        log(:warn, "skipped: contract_alerts_unavailable")
      end

      result
    end

    private

    attr_reader :migration, :subscription

    delegate :shadow_organization, to: :migration

    # ContractAlerts::CreateService refuses every alert without them: skip the run instead of logging each refusal
    def contract_alerts_available?
      License.premium? && shadow_organization.feature_flag_enabled?(:contract_alerts)
    end

    def copy_alerts
      reconcile_contract_alerts if v1_alerts.any? || contract_alerts_of_external_id.exists?
    end

    def reconcile_contract_alerts
      if contract.nil?
        log(:info, "skipped: contract_not_found")
      else
        destroy_stale_contract_alerts
        create_missing_contract_alerts if result.success?
      end
    end

    def v1_alerts
      @v1_alerts ||= subscription.alerts.includes(:thresholds, :billable_metric).order(:code).to_a
    end

    def contract_alerts_of_external_id
      UsageMonitoring::ContractAlert.where(organization_id: shadow_organization.id, contract_external_id: subscription.external_id)
    end

    def contract
      @contract ||= shadow_organization.contracts.live
        .where(external_id: subscription.external_id)
        .order(:created_at)
        .last
    end

    def contract_alerts
      @contract_alerts ||= contract.contract_alerts.includes(:thresholds).order(:code).to_a
    end

    def existing_codes
      @existing_codes ||= contract_alerts.map(&:code)
    end

    def expected_params_by_code
      @expected_params_by_code ||= v1_alerts.to_h { [it.code, expected_params(it)] }
    end

    # Both unique indexes of contract alerts skip soft-deleted rows, so a stale copy goes before its replacement
    def destroy_stale_contract_alerts
      contract_alerts.each do |contract_alert|
        reason = stale_reason(contract_alert)
        destroy_contract_alert(contract_alert, reason) if reason
        break if result.failure?
      end
    end

    def stale_reason(contract_alert)
      expected = expected_params_by_code[contract_alert.code]

      if expected.nil?
        "v1_alert_missing"
      elsif expected.is_a?(String)
        expected
      elsif !matches_expected?(contract_alert, expected)
        "content_differs"
      end
    end

    def destroy_contract_alert(contract_alert, reason)
      destruction = UsageMonitoring::ContractAlerts::DestroyService.call(alert: contract_alert)

      if destruction.success?
        existing_codes.delete(contract_alert.code)
        log(:info, "destroyed alert #{contract_alert.code}: #{reason}")
      else
        log(:warn, "cannot destroy alert #{contract_alert.code}: #{destruction.error.message}")
        result.fail_with_error!(destruction.error)
      end
    end

    def matches_expected?(contract_alert, expected)
      contract_alert.alert_type == expected[:alert_type] &&
        contract_alert.product_id == expected[:product_id] &&
        contract_alert.product_filter_id.nil? &&
        contract_alert.with_product_filters == (expected[:with_product_filters] == true) &&
        contract_alert.name == expected[:name] &&
        comparable_thresholds(contract_alert.thresholds) == comparable_thresholds(expected[:thresholds])
    end

    def comparable_thresholds(thresholds)
      thresholds
        .map { [it[:code], BigDecimal(it[:value].to_s), it[:recurring], it[:notify_on]] }
        .sort_by { |code, value, recurring, notify_on| [value, code.to_s, recurring.to_s, notify_on.join(",")] }
    end

    def create_missing_contract_alerts
      v1_alerts.each do |alert|
        copy_alert(alert)
        break if result.failure?
      end
    end

    def copy_alert(alert)
      params = expected_params_by_code[alert.code]

      if params.is_a?(String)
        log(:info, "skipped alert #{alert.code}: #{params}")
      elsif existing_codes.exclude?(alert.code)
        create_contract_alert(alert, params)
      end
    end

    def create_contract_alert(alert, params)
      creation = UsageMonitoring::ContractAlerts::CreateService.call(organization: shadow_organization, contract:, params:)
      skip_or_fail(alert, creation.error) if creation.failure?
    end

    def skip_or_fail(alert, error)
      if EXPECTED_REFUSALS.any? { error.is_a?(it) }
        log(:info, "skipped alert #{alert.code}: #{error.message}")
      else
        log(:warn, "cannot create alert #{alert.code}: #{error.message}")
        result.fail_with_error!(error)
      end
    end

    def expected_params(alert)
      case alert.alert_type
      when "current_usage_amount"
        alert_params(alert, alert_type: "usage_amount")
      when "billable_metric_current_usage_amount"
        product_alert_params(alert, alert_type: "usage_amount")
      when "billable_metric_current_usage_units"
        product_alert_params(alert, alert_type: "usage_units")
      else
        "unsupported_alert_type"
      end
    end

    def product_alert_params(alert, alert_type:)
      product_ids = shadow_product_ids_by_metric_code.fetch(alert.billable_metric.code, [])

      if product_ids.empty?
        "shadow_product_not_found"
      elsif product_ids.many?
        "shadow_product_ambiguous"
      else
        alert_params(alert, alert_type:).merge(product_id: product_ids.first, with_product_filters: true)
      end
    end

    def alert_params(alert, alert_type:)
      {
        alert_type:,
        code: alert.code,
        name: alert.name,
        thresholds: alert.thresholds.map do
          {code: it.code, value: it.value.to_s("F"), recurring: it.recurring, notify_on: it.notify_on}
        end
      }
    end

    def shadow_product_ids_by_metric_code
      @shadow_product_ids_by_metric_code ||= shadow_organization.products.metered
        .joins(:billable_metric)
        .where(billable_metrics: {code: v1_alerts.filter_map { it.billable_metric&.code }.uniq})
        .where(id: priced_product_ids)
        .distinct
        .pluck("billable_metrics.code", :id)
        .group_by(&:first)
        .transform_values { it.map(&:last) }
    end

    # Only a product priced on a live contract of the external id is accepted by ContractAlerts::CreateService
    def priced_product_ids
      live_contract_ids = shadow_organization.contracts.live.where(external_id: subscription.external_id).select(:id)

      RateCard.where(
        organization_id: shadow_organization.id,
        id: ContractRateCard.where(contract_id: live_contract_ids).select(:rate_card_id)
      ).select(:product_id)
    end

    def log(level, message)
      Rails.logger.public_send(
        level,
        "BillingEngineMigrations::CopySubscriptionAlertsService: subscription #{subscription.external_id} " \
        "(migration #{migration.id}): #{message}"
      )
    end
  end
end

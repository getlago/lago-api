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

      SubscriptionCopyLockService.call(subscription:) { copy_alerts }
      result
    end

    private

    attr_reader :migration, :subscription

    delegate :shadow_organization, to: :migration

    def copy_alerts
      if v1_alerts.any? && contract.nil?
        log(:info, "skipped: contract_not_found")
      elsif v1_alerts.any?
        v1_alerts.each do |alert|
          copy_alert(alert)
          break if result.failure?
        end
      end
    end

    def v1_alerts
      @v1_alerts ||= subscription.alerts.includes(:thresholds, :billable_metric).order(:code).to_a
    end

    def contract
      @contract ||= shadow_organization.contracts.live
        .where(external_id: subscription.external_id)
        .order(:created_at)
        .last
    end

    def existing_codes
      @existing_codes ||= contract.contract_alerts.pluck(:code)
    end

    def copy_alert(alert)
      params = expected_params(alert)

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
      product_ids = shadow_product_ids(alert.billable_metric.code)

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

    def shadow_product_ids(metric_code)
      @shadow_product_ids ||= {}
      @shadow_product_ids[metric_code] ||= shadow_organization.products.metered
        .joins(:billable_metric)
        .where(billable_metrics: {code: metric_code})
        .where(id: priced_product_ids)
        .distinct
        .limit(2)
        .pluck(:id)
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

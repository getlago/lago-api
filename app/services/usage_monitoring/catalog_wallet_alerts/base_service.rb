# frozen_string_literal: true

module UsageMonitoring
  module CatalogWalletAlerts
    class BaseService < UsageMonitoring::BaseService
      TYPE_UNIQUE_INDEXES = %w[idx_plan_wallet_alerts_alert_type_unique idx_catalog_wallet_alerts_alert_type_unique].freeze
      CODE_UNIQUE_INDEXES = {"idx_plan_wallet_alerts_code_unique" => :code, "idx_catalog_wallet_alerts_code_unique" => :code}.freeze

      private

      # Templates lock the plan wallet, so a copy sees one version of them. Contract wallets share the contract lock with
      # its end and plan change, then lock the wallet in BaselineService's mode, which a create raises it to.
      def lock_wallet(wallet)
        if wallet.is_a?(PlanWallet)
          wallet.lock!
          result.not_found_failure!(resource: "plan_wallet") if wallet.discarded?
        else
          wallet.contract.lock!("FOR SHARE")
          wallet.lock!("FOR NO KEY UPDATE")

          if wallet.discarded?
            result.not_found_failure!(resource: "contract_wallet")
          elsif Contract::LIVE_STATUSES.exclude?(wallet.contract.status)
            result.forbidden_failure!(code: "contract_not_live")
          elsif wallet.terminated_at?
            result.forbidden_failure!(code: "wallet_alerts_read_only")
          end
        end
      end

      def wallet_of(alert)
        alert.is_a?(PlanWalletAlert) ? alert.plan_wallet : alert.catalog_wallet
      end

      # The checks of every alert family, then the wallet rules: values are cents, so a fraction is refused
      # rather than truncated. A balance never goes below 0, so a balance alert has no line below it either,
      # a recurring one included
      def validate_thresholds(thresholds, alert_type)
        validation = Thresholds::ValidateService.call(thresholds:)
        return result.fail_with_error!(validation.error) unless validation.success?

        wallet_values = thresholds.all? { BigDecimal(it[:value].to_s).frac.zero? } &&
          (alert_type != "balance" || lowest_line(thresholds) >= 0)
        result.single_validation_failure!(field: :thresholds, error_code: "value_is_invalid") unless wallet_values
      end

      # A recurring step adds lines below the lowest one-time threshold, from 0 when there is none
      def lowest_line(thresholds)
        recurring, one_time = thresholds.partition { ActiveModel::Type::Boolean.new.cast(it[:recurring]) }
        lowest = one_time.map { BigDecimal(it[:value].to_s) }.min

        if recurring.empty?
          lowest
        else
          (lowest || 0) - BigDecimal(recurring.first[:value].to_s)
        end
      end

      def validate_single_values(params, fields)
        invalid = fields.reject { single_value?(params[it]) }
        result.validation_failure!(errors: invalid.index_with { ["value_is_invalid"] }) if invalid.any?
      end
    end
  end
end

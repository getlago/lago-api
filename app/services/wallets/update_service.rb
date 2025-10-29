# frozen_string_literal: true

module Wallets
  class UpdateService < BaseService
    def initialize(wallet:, params:)
      @wallet = wallet
      @params = params

      super
    end

    activity_loggable(
      action: "wallet.updated",
      record: -> { wallet }
    )

    def call
      return result.not_found_failure!(resource: "wallet") unless wallet
      return result unless valid_expiration_at?(expiration_at: params[:expiration_at])
      return result unless valid_recurring_transaction_rules?
      return result unless valid_limitations?

      ActiveRecord::Base.transaction do
        wallet.name = params[:name] if params.key?(:name)
        wallet.priority = params[:priority] if params.key?(:priority)
        wallet.expiration_at = params[:expiration_at] if params.key?(:expiration_at)
        if params.key?(:invoice_requires_successful_payment)
          wallet.invoice_requires_successful_payment = ActiveModel::Type::Boolean.new.cast(params[:invoice_requires_successful_payment])
        end
        wallet.paid_top_up_min_amount_cents = params[:paid_top_up_min_amount_cents] if params.key?(:paid_top_up_min_amount_cents)
        wallet.paid_top_up_max_amount_cents = params[:paid_top_up_max_amount_cents] if params.key?(:paid_top_up_max_amount_cents)
        if params[:recurring_transaction_rules] && License.premium?
          Wallets::RecurringTransactionRules::UpdateService.call!(wallet:, params: params[:recurring_transaction_rules])
        end

        wallet.recurring_transaction_rules.find_each { |rule| validate_rule!(rule:) }

        if params.key?(:applies_to)
          wallet.allowed_fee_types = params[:applies_to][:fee_types] if params[:applies_to].key?(:fee_types)
        end

        process_billable_metrics

        wallet.save!
      end

      SendWebhookJob.perform_later("wallet.updated", wallet)
      Wallets::Balance::RefreshOngoingService.call(wallet: wallet.reload)

      result.wallet = wallet
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :wallet, :params

    def validate_rule!(rule:)
      return unless rule.fixed?

      credit_amount = rule.paid_credits
      return if credit_amount.nil? || credit_amount.zero?

      validator = Validators::WalletTransactionAmountLimitsValidator.new(
        result,
        wallet:,
        credits_amount: credit_amount.to_s,
        ignore_validation: rule.ignore_paid_top_up_limits
      )

      unless validator.valid?
        result.single_validation_failure!(field: :recurring_transaction_rules, error_code: "invalid_recurring_rule")
        result.raise_if_error!
      end
    end

    def valid_recurring_transaction_rules?
      Wallets::ValidateRecurringTransactionRulesService.new(result, **params).valid?
    end

    def valid_expiration_at?(expiration_at:)
      return true if Validators::ExpirationDateValidator.valid?(expiration_at)

      result.single_validation_failure!(field: :expiration_at, error_code: "invalid_date")
      false
    end

    def valid_limitations?
      result.billable_metrics = billable_metrics
      result.billable_metric_identifiers = billable_metric_identifiers
      Wallets::ValidateLimitationsService.new(result, **params).valid?
    end

    def process_billable_metrics
      # In case of adding new type of limitation in wallet_targets, query from below should use compact to avoid nil values in the array
      existing_wallet_billable_metric_ids = wallet.wallet_targets.pluck(:billable_metric_id)

      billable_metrics.each do |bm|
        next if existing_wallet_billable_metric_ids.include?(bm.id)

        WalletTarget.create!(wallet:, billable_metric: bm, organization_id: wallet.organization_id)
      end

      sanitize_wallet_billable_metrics(existing_wallet_billable_metric_ids) if existing_wallet_billable_metric_ids.present?
    end

    def sanitize_wallet_billable_metrics(existing_wallet_billable_metric_ids)
      not_needed_wallet_target_ids = existing_wallet_billable_metric_ids - billable_metrics.pluck(:id)
      not_needed_wallet_target_ids.each do |wallet_billable_metric_id|
        WalletTarget.find_by(wallet:, billable_metric_id: wallet_billable_metric_id, organization: wallet.organization)&.destroy!
      end
    end

    def billable_metric_identifiers
      return [] if params[:applies_to].blank?

      key = api_context? ? :billable_metric_codes : :billable_metric_ids

      return [] if params[:applies_to][key].blank?

      params[:applies_to][key]&.compact&.uniq
    end

    def billable_metrics
      return @billable_metrics if defined?(@billable_metrics)
      return [] if billable_metric_identifiers.blank?

      @billable_metrics = if api_context?
        BillableMetric.where(code: billable_metric_identifiers, organization_id: wallet.organization_id)
      else
        BillableMetric.where(id: billable_metric_identifiers, organization_id: wallet.organization_id)
      end
    end
  end
end

# frozen_string_literal: true

module Wallets
  class CreateService < BaseService
    def initialize(params:)
      @params = params
      super
    end

    activity_loggable(
      action: "wallet.created",
      record: -> { result.wallet }
    )

    def call
      result.billable_metric_identifiers = billable_metric_identifiers
      result.billable_metrics = billable_metrics

      return result unless valid?

      attributes = {
        organization_id: result.current_customer.organization_id,
        customer_id: result.current_customer.id,
        name: params[:name],
        rate_amount: params[:rate_amount],
        expiration_at: params[:expiration_at],
        status: :active,
        paid_top_up_min_amount_cents: params[:paid_top_up_min_amount_cents],
        paid_top_up_max_amount_cents: params[:paid_top_up_max_amount_cents]
      }

      attributes[:priority] = params[:priority] if params.key?(:priority)

      if params.key?(:invoice_requires_successful_payment)
        attributes[:invoice_requires_successful_payment] = ActiveModel::Type::Boolean.new.cast(params[:invoice_requires_successful_payment]) || false
      end

      if params.key?(:applies_to)
        attributes[:allowed_fee_types] = params[:applies_to][:fee_types] if params[:applies_to].key?(:fee_types)
      end

      wallet = Wallet.new(attributes)

      ActiveRecord::Base.transaction do
        if params[:currency].present?
          Customers::UpdateCurrencyService.call!(customer: result.current_customer, currency: params[:currency])
        end

        wallet.currency = wallet.customer.currency
        wallet.save!

        validate_wallet_initial_amount! wallet

        if params[:recurring_transaction_rules].present?
          Wallets::RecurringTransactionRules::CreateService.call!(wallet:, wallet_params: params)
        end

        billable_metrics.each do |bm|
          WalletTarget.create!(wallet:, billable_metric: bm, organization_id: wallet.organization_id)
        end
      end

      result.wallet = wallet

      SendWebhookJob.perform_later("wallet.created", wallet)

      WalletTransactions::CreateJob.perform_later(
        organization_id: params[:organization_id],
        params: {
          wallet_id: wallet.id,
          paid_credits: params[:paid_credits],
          granted_credits: params[:granted_credits],
          source: :manual,
          metadata: params[:transaction_metadata],
          name: params[:transaction_name],
          ignore_paid_top_up_limits: params[:ignore_paid_top_up_limits_on_creation]
        }
      )

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :params

    def valid?
      Wallets::ValidateService.new(result, **params).valid?
    end

    def validate_wallet_initial_amount!(wallet)
      return unless positive_paid_credit_amount?

      Validators::WalletTransactionAmountLimitsValidator.new(
        result,
        wallet:,
        credits_amount: params[:paid_credits],
        ignore_validation: params[:ignore_paid_top_up_limits_on_creation]
      ).raise_if_invalid!
    end

    def positive_paid_credit_amount?
      BigDecimal(params[:paid_credits]).positive?
    rescue ArgumentError, TypeError
      false
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
        BillableMetric.where(code: billable_metric_identifiers, organization_id: params[:organization_id])
      else
        BillableMetric.where(id: billable_metric_identifiers, organization_id: params[:organization_id])
      end
    end
  end
end

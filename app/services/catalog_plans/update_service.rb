# frozen_string_literal: true

module CatalogPlans
  class UpdateService < BaseService
    include Entitlement::Concerns::OwnerLockConcern
    include Metadata::ReplaceItemParams

    Result = BaseResult[:catalog_plan]

    def initialize(catalog_plan:, params:, send_webhook: true, partial_metadata: false, delete_metadata_key: nil, skip_unchanged_metadata: false)
      @catalog_plan = catalog_plan
      @params = params
      @send_webhook = send_webhook
      @partial_metadata = partial_metadata
      @delete_metadata_key = delete_metadata_key
      @skip_unchanged_metadata = skip_unchanged_metadata
      super()
    end

    activity_loggable(
      action: "plan.updated",
      record: -> { catalog_plan },
      condition: -> { !skip_unchanged_metadata }
    )

    def call
      return result.not_found_failure!(resource: "plan") unless catalog_plan

      if malformed_metadata?(params[:metadata])
        return result.single_validation_failure!(field: :metadata, error_code: "value_is_invalid")
      end

      changed = true

      ActiveRecord::Base.transaction do
        lock_plan!(catalog_plan)
        check_editable!

        if skip_unchanged_metadata && params.except(:metadata).empty? && unchanged_metadata?
          changed = false
        else
          log_activity { apply_changes }
        end
      end

      result.catalog_plan = catalog_plan
      SendWebhookJob.perform_after_commit("plan.updated", catalog_plan) if send_webhook && changed
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::RecordNotUnique => e
      unique_index_failure!(e, "index_catalog_plans_on_organization_id_and_code" => :code)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e.result.error)
    end

    private

    attr_reader :catalog_plan, :params, :send_webhook, :partial_metadata, :delete_metadata_key, :skip_unchanged_metadata

    def apply_changes
      catalog_plan.name = params[:name] if params.key?(:name)
      catalog_plan.code = params[:code] if params.key?(:code)
      catalog_plan.description = params[:description] if params.key?(:description)
      catalog_plan.invoice_display_name = params[:invoice_display_name] if params.key?(:invoice_display_name)
      catalog_plan.currency = params[:currency] if params.key?(:currency)
      catalog_plan.updated_at = Time.current if writes_metadata?
      catalog_plan.save!

      write_metadata! if writes_metadata?
      apply_taxes
      result
    end

    # The activity log is produced here, and not by the middleware, when unchanged metadata is
    # skipped: whether the call changes anything is only known once the plan is locked.
    def log_activity(&)
      return yield unless skip_unchanged_metadata

      Utils::ActivityLog.produce(catalog_plan, "plan.updated", after_commit: true, &)
    end

    def writes_metadata?
      params.key?(:metadata) || !delete_metadata_key.nil?
    end

    def write_metadata!
      return replace_metadata!(catalog_plan, params[:metadata], partial: partial_metadata) if delete_metadata_key.nil?

      current = catalog_plan.metadata
      result.not_found_failure!(resource: "metadata").raise_if_error! unless current

      replace_metadata!(catalog_plan, current.value.to_h.except(delete_metadata_key.to_s))
    end

    def unchanged_metadata?
      current = catalog_plan.metadata&.value

      if delete_metadata_key
        result.not_found_failure!(resource: "metadata").raise_if_error! unless catalog_plan.metadata
        return current == current.to_h.except(delete_metadata_key.to_s)
      end

      return false unless params.key?(:metadata)

      incoming = params[:metadata]&.transform_keys(&:to_s)
      return current == incoming unless partial_metadata

      incoming.blank? || (!current.nil? && current.merge(incoming) == current)
    end

    def check_editable!
      # A contract prices against the plan by reference — it serializes the
      # plan_code through the association (so the code must stay stable) and its
      # fees invoice in the plan currency. Once a contract is attached both are
      # frozen; name, description and invoice display name stay editable.
      if (code_change_requested? || currency_change_requested?) && catalog_plan.attached_to_contracts?
        result.single_validation_failure!(field: :plan, error_code: "plan_locked").raise_if_error!
      end

      # Plan-level rate cards freeze the currency too, before any contract: the
      # cards were validated against it and changing it would desync them.
      if currency_change_requested? && catalog_plan.applied_rate_cards.exists?
        result.single_validation_failure!(field: :currency, error_code: "not_editable_with_applied_rate_cards").raise_if_error!
      end

      # Wallet templates share the plan currency, checked when they are added.
      if currency_change_requested? && catalog_plan.wallets.exists?
        result.single_validation_failure!(field: :currency, error_code: "not_editable_with_wallets").raise_if_error!
      end
    end

    def apply_taxes
      return unless params.key?(:tax_codes) && !params[:tax_codes].nil?

      CatalogPlans::ApplyTaxesService.call!(catalog_plan:, tax_codes: params[:tax_codes])
    end

    def code_change_requested?
      params.key?(:code) && params[:code] != catalog_plan.code
    end

    def currency_change_requested?
      params.key?(:currency) && params[:currency] != catalog_plan.currency
    end
  end
end

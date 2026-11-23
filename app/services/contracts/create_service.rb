# frozen_string_literal: true

module Contracts
  # Records a new agreement. The plan is optional by design: a plan-less
  # contract prices through directly attached rate cards. The contract is
  # active when its start has arrived, pending when it starts in the future
  # — lifecycle state lives in the status, the dates only carry the window.
  # A draft stays a draft whatever its start date, until it is published.
  class CreateService < BaseService
    include CustomerTimezone
    include SettingsResolvable

    Result = BaseResult[:contract, :payment_method]

    def initialize(organization:, params:)
      @organization = organization
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "customer") unless customer

      if params[:plan_code].present? && catalog_plan.nil?
        return result.not_found_failure!(resource: "plan")
      end

      # Date columns: a malformed value would silently cast to nil instead of
      # failing, so formats are rejected explicitly.
      %i[billing_anchor_date started_at ended_at].each do |field|
        if params[field].present? && !Utils::Datetime.valid_format?(params[field])
          return result.single_validation_failure!(field:, error_code: "value_is_invalid")
        end
      end

      # Only a draft is chosen by the caller: the start date decides between
      # pending and active. A null status means omitted, as SDKs send every
      # optional field.
      if !params[:status].nil? && !draft?
        return result.single_validation_failure!(field: :status, error_code: "value_is_invalid")
      end

      # started_at defaults to the creation time, so a draft without one would
      # bill from its creation once published.
      if draft? && params[:started_at].blank?
        return result.single_validation_failure!(field: :started_at, error_code: "value_is_mandatory")
      end

      # A window that already closed cannot be created: nothing would ever
      # terminate it, leaving a zombie active contract.
      if params[:ended_at].present? && ended_at_in_customer_timezone <= Time.current
        return result.single_validation_failure!(field: :ended_at, error_code: "already_ended")
      end

      # One live agreement per external id. Replacement flows (upgrade,
      # downgrade, renewal) will create their pending sibling explicitly when
      # they exist; a blind second create is a mistake, not a replacement.
      # Advisory under concurrency — the partial unique index closes the race.
      if organization.contracts.where(status: Contract::LIVE_STATUSES, external_id: params[:external_id]).exists?
        return result.single_validation_failure!(field: :external_id, error_code: "value_already_exists")
      end

      if (failure = settings_references_failure)
        return failure
      end

      started_at = params[:started_at].present? ? started_at_in_customer_timezone : Time.current

      ActiveRecord::Base.transaction do
        Customers::LockService.call!(customer:, scope: :billing_schedule) do
          contract = organization.contracts.new(
            customer:,
            catalog_plan:,
            external_id: params[:external_id],
            code: params[:code],
            name: params[:name],
            billing_time: params[:billing_time].presence || "calendar",
            billing_anchor_date: params[:billing_anchor_date],
            started_at:,
            ended_at: ended_at_in_customer_timezone,
            status: draft? ? :draft : :pending
          )
          apply_settings(contract)
          contract.save!
          InvoiceCustomSections::AttachToResourceService.call!(resource: contract, params:)

          if contract.catalog_plan
            Contracts::MaterializeRateCardsService.call!(contract:)
            Contracts::MaterializeWalletsService.call!(contract:) if organization.catalog_wallets_enabled?
          end
          result.contract = contract
          Utils::ActivityLog.produce_after_commit(contract, "contract.created")
          SendWebhookJob.perform_after_commit("contract.created", contract)
          Contracts::ActivateService.call!(contract:, timestamp: Time.current) unless contract.draft? || started_at.future?
        end
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::RecordNotUnique => e
      if violated_unique_index(e) == "index_contracts_on_live_external_id"
        result.single_validation_failure!(field: :external_id, error_code: "value_already_exists")
      else
        unique_index_failure!(e, "index_contracts_on_organization_id_external_id_code" => :code)
      end
    rescue BaseService::FailedResult => e
      e.result
    rescue BaseLockService::FailedToAcquireLock => e
      result.lock_acquisition_failure!(message: e.message, error: e)
    end

    private

    attr_reader :organization, :params

    def customer
      @customer ||= organization.customers.find_by(external_id: params[:external_customer_id])
    end

    def catalog_plan
      @catalog_plan ||= organization.catalog_plans.find_by(code: params[:plan_code])
    end

    def draft?
      params[:status] == "draft"
    end

    # Read through the CustomerTimezone suffix: a datetime without an offset
    # means the customer's wall clock, not the application's —
    # String#in_time_zone parses a naive value in the customer's zone and
    # respects explicit offsets. Nil when the param is absent.
    def started_at
      params[:started_at].presence
    end

    def ended_at
      params[:ended_at].presence
    end
  end
end

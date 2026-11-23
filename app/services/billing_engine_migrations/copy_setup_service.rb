# frozen_string_literal: true

module BillingEngineMigrations
  class CopySetupService < BaseService
    Result = BaseResult[:records]

    Record = Data.define(:resource, :code, :outcome, :error)

    # Contract invoices stay drafts while the shadow organization only mirrors billing.
    SHADOW_INVOICE_GRACE_PERIOD_DAYS = 365

    BILLING_ENTITY_ATTRIBUTES = %i[
      code name address_line1 address_line2 city state zipcode country default_currency timezone
      legal_name legal_number tax_identification_number
    ].freeze

    BILLABLE_METRIC_ATTRIBUTES = %i[
      code name description aggregation_type field_name expression recurring
      rounding_function rounding_precision weighted_interval
    ].freeze

    def initialize(migration:, dry_run: true)
      @migration = migration
      @dry_run = dry_run
      super
    end

    def call
      result.records = []
      return result unless migration.shadowing?

      copy_taxes
      copy_billing_entities
      copy_billable_metrics

      result
    end

    private

    attr_reader :migration, :dry_run

    delegate :organization, :shadow_organization, to: :migration

    def copy_taxes
      organization.taxes.order(:code).each do |tax|
        copy("tax", tax.code, shadow_organization.taxes) do
          params = tax.slice(:code, :name, :rate, :description).symbolize_keys
          Taxes::CreateService.call(organization: shadow_organization, params:)
        end
      end
    end

    def copy_billing_entities
      organization.billing_entities.reorder(:code).preload(:taxes).each do |billing_entity|
        copy("billing_entity", billing_entity.code, shadow_organization.billing_entities) do
          BillingEntities::CreateService.call(organization: shadow_organization, params: billing_entity_params(billing_entity))
        end
      end
    end

    def copy_billable_metrics
      organization.billable_metrics.order(:code).preload(:filters).each do |billable_metric|
        copy("billable_metric", billable_metric.code, shadow_organization.billable_metrics) do
          BillableMetrics::CreateService.call(**billable_metric_params(billable_metric))
        end
      end
    end

    def copy(resource, code, shadow_records)
      outcome, error = if shadow_records.exists?(code:)
        :skipped
      elsif dry_run
        :would_create
      else
        creation = yield
        creation.success? ? :created : [:failed, creation.error]
      end

      result.records << Record.new(resource:, code:, outcome:, error:)
    end

    def billing_entity_params(billing_entity)
      billing_entity.slice(*BILLING_ENTITY_ATTRIBUTES).symbolize_keys.merge(
        tax_codes: billing_entity.taxes.map(&:code),
        billing_configuration: {invoice_grace_period: SHADOW_INVOICE_GRACE_PERIOD_DAYS}
      )
    end

    def billable_metric_params(billable_metric)
      billable_metric.slice(*BILLABLE_METRIC_ATTRIBUTES).symbolize_keys.merge(
        organization_id: shadow_organization.id,
        filters: billable_metric.filters.map { |filter| {key: filter.key, values: filter.values} }
      )
    end
  end
end

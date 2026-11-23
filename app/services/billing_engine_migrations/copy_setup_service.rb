# frozen_string_literal: true

module BillingEngineMigrations
  class CopySetupService < BaseService
    Result = BaseResult[:records]

    Record = Data.define(:resource, :code, :outcome, :error, :mismatches)

    # Contract invoices stay drafts while the shadow organization only mirrors billing.
    SHADOW_INVOICE_GRACE_PERIOD_DAYS = 365

    SHADOW_BILLING_ENTITY_PARAMS = {
      billing_configuration: {invoice_grace_period: SHADOW_INVOICE_GRACE_PERIOD_DAYS},
      email_settings: [],
      eu_tax_management: false
    }.freeze

    TAX_ATTRIBUTES = %i[code name rate description].freeze

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
        params = tax_attributes(tax)
        shadow_tax = shadow_organization.taxes.find_by(code: tax.code)

        if shadow_tax
          add_existing_record("tax", tax.code, mismatched_attributes(params, tax_attributes(shadow_tax)))
        else
          create("tax", tax.code) { Taxes::CreateService.call(organization: shadow_organization, params:) }
        end
      end
    end

    def copy_billing_entities
      organization.billing_entities.reorder(:code).preload(:taxes).each do |billing_entity|
        attributes = billing_entity_attributes(billing_entity)
        shadow_entity = shadow_organization.billing_entities.find_by(code: billing_entity.code)

        if shadow_entity
          reconcile_billing_entity(shadow_entity, mismatched_attributes(attributes, billing_entity_attributes(shadow_entity)))
        else
          create("billing_entity", billing_entity.code) do
            BillingEntities::CreateService.call(
              organization: shadow_organization,
              params: attributes.merge(SHADOW_BILLING_ENTITY_PARAMS)
            )
          end
        end
      end
    end

    def copy_billable_metrics
      organization.billable_metrics.order(:code).preload(:filters).each do |billable_metric|
        attributes = billable_metric_attributes(billable_metric)
        shadow_metric = shadow_organization.billable_metrics.find_by(code: billable_metric.code)

        if shadow_metric
          mismatches = mismatched_attributes(attributes, billable_metric_attributes(shadow_metric))
          add_existing_record("billable_metric", billable_metric.code, mismatches)
        else
          create("billable_metric", billable_metric.code) do
            BillableMetrics::CreateService.call(**attributes, organization_id: shadow_organization.id)
          end
        end
      end
    end

    def create(resource, code)
      return add_record(resource, code, :would_create) if dry_run

      creation = yield
      return add_record(resource, code, :failed, error: creation.error) if creation.failure?

      add_record(resource, code, :created)
    end

    # An existing entity keeps its other attributes, but must never finalize invoices or email customers.
    def reconcile_billing_entity(shadow_entity, mismatches)
      code = shadow_entity.code
      return add_existing_record("billing_entity", code, mismatches) if shadow_settings?(shadow_entity)
      return add_record("billing_entity", code, mismatches.any? ? :mismatch : :would_update, mismatches:) if dry_run

      update = BillingEntities::UpdateService.call(billing_entity: shadow_entity, params: SHADOW_BILLING_ENTITY_PARAMS)
      return add_record("billing_entity", code, :failed, error: update.error) if update.failure?

      add_record("billing_entity", code, mismatches.any? ? :mismatch : :updated, mismatches:)
    end

    def shadow_settings?(billing_entity)
      billing_entity.invoice_grace_period == SHADOW_INVOICE_GRACE_PERIOD_DAYS &&
        billing_entity.email_settings.blank? &&
        !billing_entity.eu_tax_management
    end

    def add_existing_record(resource, code, mismatches)
      add_record(resource, code, mismatches.any? ? :mismatch : :skipped, mismatches:)
    end

    def add_record(resource, code, outcome, error: nil, mismatches: [])
      result.records << Record.new(resource:, code:, outcome:, error:, mismatches:)
    end

    def mismatched_attributes(attributes, shadow_attributes)
      attributes.keys.reject { |key| attributes[key] == shadow_attributes[key] }
    end

    def tax_attributes(tax)
      tax.slice(*TAX_ATTRIBUTES).symbolize_keys
    end

    def billing_entity_attributes(billing_entity)
      billing_entity.slice(*BILLING_ENTITY_ATTRIBUTES).symbolize_keys.merge(
        tax_codes: billing_entity.taxes.map(&:code).sort
      )
    end

    def billable_metric_attributes(billable_metric)
      billable_metric.slice(*BILLABLE_METRIC_ATTRIBUTES).symbolize_keys.merge(
        filters: billable_metric.filters
          .map { |filter| {key: filter.key, values: filter.values.sort} }
          .sort_by { |filter| filter[:key] }
      )
    end
  end
end

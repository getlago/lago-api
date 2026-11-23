# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::CopySetupService, :premium do
  subject(:result) { described_class.call(migration:, dry_run:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:tax) { create(:tax, organization:, code: "vat_fr", rate: 20.0, description: "French VAT") }
  let_it_be(:other_tax) { create(:tax, organization:, code: "vat_de", rate: 19.0) }
  let_it_be(:billing_entity) do
    organization.default_billing_entity.tap do |entity|
      entity.update!(
        code: "entity_fr",
        address_line1: "1 rue de la Paix",
        city: "Paris",
        zipcode: "75002",
        country: "FR",
        default_currency: "EUR",
        timezone: "Europe/Paris",
        legal_name: "Entity SAS",
        legal_number: "123456789",
        tax_identification_number: "FR123456789",
        invoice_grace_period: 3,
        email_settings: ["invoice.finalized"],
        eu_tax_management: true
      )
      create(:billing_entity_applied_tax, billing_entity: entity, tax:, organization:)
    end
  end
  let_it_be(:archived_entity) { create(:billing_entity, :archived, organization:, code: "entity_archived") }
  let_it_be(:billable_metric) do
    create(:sum_billable_metric, organization:, code: "api_calls", rounding_function: "round", rounding_precision: 2)
  end
  let_it_be(:filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us]) }
  let_it_be(:recurring_metric) { create(:weighted_sum_billable_metric, :recurring, organization:, code: "seats") }

  let(:shadow_organization) do
    create(:organization, webhook_url: nil, premium_integrations: ["multi_entities_enterprise"])
  end
  let(:migration) { create(:billing_engine_migration, organization:, shadow_organization:, status:) }
  let(:status) { "shadowing" }
  let(:dry_run) { false }

  def outcomes
    result.records.map { |record| [record.resource, record.code, record.outcome] }
  end

  it "copies the taxes, the active billing entities and the billable metrics with the same codes" do
    expect(result).to be_success
    expect(outcomes).to eq(
      [
        ["tax", "vat_de", :created],
        ["tax", "vat_fr", :created],
        ["billing_entity", "entity_fr", :created],
        ["billable_metric", "api_calls", :created],
        ["billable_metric", "seats", :created]
      ]
    )

    expect(shadow_organization.taxes.find_by(code: "vat_fr")).to have_attributes(
      name: tax.name,
      rate: 20.0,
      description: "French VAT"
    )
    expect(shadow_organization.taxes.find_by(code: "vat_de")).to have_attributes(name: other_tax.name, rate: 19.0)
    expect(shadow_organization.billing_entities.where(code: "entity_archived")).to be_empty
  end

  it "copies the billing entity with drafts kept, no emails and no EU tax management" do
    result

    shadow_entity = shadow_organization.billing_entities.find_by(code: "entity_fr")
    expect(shadow_entity).to have_attributes(
      name: billing_entity.name,
      address_line1: "1 rue de la Paix",
      city: "Paris",
      zipcode: "75002",
      country: "FR",
      default_currency: "EUR",
      timezone: "Europe/Paris",
      legal_name: "Entity SAS",
      legal_number: "123456789",
      tax_identification_number: "FR123456789",
      invoice_grace_period: described_class::SHADOW_INVOICE_GRACE_PERIOD_DAYS,
      email_settings: [],
      eu_tax_management: false
    )
    expect(shadow_entity.taxes.map(&:code)).to eq(["vat_fr"])
  end

  it "copies the billable metrics with their filters" do
    result

    shadow_metric = shadow_organization.billable_metrics.find_by(code: "api_calls")
    expect(shadow_metric).to have_attributes(
      name: billable_metric.name,
      description: billable_metric.description,
      aggregation_type: "sum_agg",
      field_name: "item_id",
      expression: billable_metric.expression,
      recurring: false,
      rounding_function: "round",
      rounding_precision: 2
    )
    expect(shadow_metric.filters.map { [it.key, it.values] }).to eq([["region", %w[eu us]]])
    expect(shadow_organization.billable_metrics.find_by(code: "seats")).to have_attributes(
      aggregation_type: "weighted_sum_agg",
      weighted_interval: "seconds",
      field_name: "value",
      recurring: true
    )
  end

  context "when the organization has webhook endpoints and a payment provider" do
    before { create(:stripe_provider, organization:) }

    it "does not copy them" do
      result

      expect(organization.webhook_endpoints).to be_present
      expect(shadow_organization.webhook_endpoints).to be_empty
      expect(shadow_organization.payment_providers).to be_empty
    end
  end

  context "when it is a dry run" do
    let(:dry_run) { true }

    it "lists the records it would create and writes nothing" do
      expect { result }.not_to change { shadow_organization.taxes.count + shadow_organization.billable_metrics.count }

      expect(outcomes).to eq(
        [
          ["tax", "vat_de", :would_create],
          ["tax", "vat_fr", :would_create],
          ["billing_entity", "entity_fr", :would_create],
          ["billable_metric", "api_calls", :would_create],
          ["billable_metric", "seats", :would_create]
        ]
      )
      expect(shadow_organization.billing_entities.where(code: "entity_fr")).to be_empty
    end
  end

  context "when the shadow organization already has some of the codes" do
    before do
      create(:tax, organization: shadow_organization, **other_tax.slice(:code, :name, :rate, :description).symbolize_keys)
      create(:tax, organization: shadow_organization, code: "vat_fr", name: tax.name, rate: 5.5, description: "French VAT")
      create(:billable_metric, organization: shadow_organization, code: "api_calls")
    end

    it "skips the identical ones, reports the different ones and creates the others" do
      expect(outcomes).to eq(
        [
          ["tax", "vat_de", :skipped],
          ["tax", "vat_fr", :mismatch],
          ["billing_entity", "entity_fr", :created],
          ["billable_metric", "api_calls", :mismatch],
          ["billable_metric", "seats", :created]
        ]
      )

      records = result.records.index_by(&:code)
      expect(records["vat_de"].mismatches).to be_empty
      expect(records["vat_fr"].mismatches).to eq([:rate])
      expect(records["api_calls"].mismatches).to include(:aggregation_type, :field_name, :filters)
      expect(shadow_organization.taxes.find_by(code: "vat_fr").rate).to eq(5.5)
      expect(shadow_organization.billable_metrics.find_by(code: "api_calls").aggregation_type).to eq("count_agg")
    end
  end

  context "when the shadow organization already has the billing entity" do
    let(:shadow_entity) do
      shadow_organization.default_billing_entity.tap do |entity|
        entity.update!(
          **billing_entity.slice(*described_class::BILLING_ENTITY_ATTRIBUTES).symbolize_keys,
          invoice_grace_period: 0,
          email_settings: ["invoice.finalized"],
          eu_tax_management: true
        )
        shadow_tax = create(:tax, organization: shadow_organization, **tax.slice(:code, :name, :rate, :description).symbolize_keys)
        create(:billing_entity_applied_tax, billing_entity: entity, tax: shadow_tax, organization: shadow_organization)
      end
    end

    before { shadow_entity }

    def billing_entity_record
      result.records.find { it.resource == "billing_entity" }
    end

    it "keeps its invoices as drafts, without emails or EU tax management" do
      expect(billing_entity_record).to have_attributes(code: "entity_fr", outcome: :updated, mismatches: [])
      expect(shadow_entity.reload).to have_attributes(
        invoice_grace_period: described_class::SHADOW_INVOICE_GRACE_PERIOD_DAYS,
        email_settings: [],
        eu_tax_management: false
      )
      expect(shadow_organization.billing_entities.where(code: "entity_fr").count).to eq(1)
    end

    context "when its other attributes differ" do
      before { shadow_entity.update!(default_currency: "USD", timezone: "UTC") }

      it "reports the differences and still keeps its invoices as drafts" do
        expect(billing_entity_record).to have_attributes(outcome: :mismatch, mismatches: %i[default_currency timezone])
        expect(shadow_entity.reload).to have_attributes(
          default_currency: "USD",
          invoice_grace_period: described_class::SHADOW_INVOICE_GRACE_PERIOD_DAYS
        )
      end
    end

    context "when it is a dry run" do
      let(:dry_run) { true }

      it "reports the update and writes nothing" do
        expect(billing_entity_record).to have_attributes(outcome: :would_update, mismatches: [])
        expect(shadow_entity.reload.invoice_grace_period).to eq(0)
      end
    end
  end

  context "when the copy already ran" do
    before { described_class.call(migration:, dry_run: false) }

    it "creates nothing" do
      expect { result }.not_to change { shadow_organization.billing_entities.count }

      expect(result.records.map(&:outcome).uniq).to eq([:skipped])
    end
  end

  context "when a record cannot be created" do
    let(:shadow_organization) { create(:organization, webhook_url: nil) }

    it "reports the failure and copies the other records" do
      expect(outcomes).to eq(
        [
          ["tax", "vat_de", :created],
          ["tax", "vat_fr", :created],
          ["billing_entity", "entity_fr", :failed],
          ["billable_metric", "api_calls", :created],
          ["billable_metric", "seats", :created]
        ]
      )
      expect(result.records.find { it.outcome == :failed }.error).to be_a(BaseService::ForbiddenFailure)
    end
  end

  context "when the migration is not shadowing" do
    let(:status) { "paused" }

    it "copies nothing" do
      expect { result }.not_to change { shadow_organization.taxes.count }

      expect(result.records).to be_empty
    end
  end
end

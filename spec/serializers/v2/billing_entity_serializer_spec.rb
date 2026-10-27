# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::BillingEntitySerializer do
  subject(:payload) { described_class.new(billing_entity, includes:).serialize }

  let_it_be(:organization) { create_default(:organization) }
  let(:billing_entity) do
    create(
      :billing_entity,
      organization:,
      net_payment_term: 30,
      subscription_invoice_issuing_date_anchor: "current_period_end",
      subscription_invoice_issuing_date_adjustment: "keep_anchor"
    )
  end
  let(:includes) { [] }

  it "serializes flat settings without payment terms or relationships" do
    expect(payload).to eq(
      lago_id: billing_entity.id,
      code: billing_entity.code,
      name: billing_entity.name,
      default_currency: billing_entity.default_currency,
      country: billing_entity.country,
      address_line1: billing_entity.address_line1,
      address_line2: billing_entity.address_line2,
      phone: billing_entity.phone,
      city: billing_entity.city,
      state: billing_entity.state,
      zipcode: billing_entity.zipcode,
      einvoicing: billing_entity.einvoicing,
      email: billing_entity.email,
      legal_name: billing_entity.legal_name,
      legal_number: billing_entity.legal_number,
      timezone: billing_entity.timezone,
      email_settings: billing_entity.email_settings,
      document_numbering: billing_entity.document_numbering,
      document_number_prefix: billing_entity.document_number_prefix,
      tax_identification_number: billing_entity.tax_identification_number,
      finalize_zero_amount_invoice: billing_entity.finalize_zero_amount_invoice,
      invoice_footer: billing_entity.invoice_footer,
      invoice_grace_period: billing_entity.invoice_grace_period,
      periodic_invoice_issuing_date_anchor: "current_period_end",
      periodic_invoice_issuing_date_adjustment: "keep_anchor",
      document_locale: billing_entity.document_locale,
      eu_tax_management: billing_entity.eu_tax_management,
      is_default: false,
      logo_url: nil,
      created_at: billing_entity.created_at.iso8601,
      updated_at: billing_entity.updated_at.iso8601,
      deleted_at: nil
    )
  end

  context "with the default entity" do
    let(:billing_entity) { organization.default_billing_entity }

    it "identifies the default entity" do
      expect(payload[:is_default]).to be(true)
    end
  end

  context "with expansions" do
    let(:includes) { %i[taxes selected_invoice_custom_sections] }
    let(:tax) { create(:tax, organization:) }
    let(:section) { create(:invoice_custom_section, organization:) }

    before do
      create(:billing_entity_applied_tax, organization:, billing_entity:, tax:)
      create(:billing_entity_applied_invoice_custom_section, organization:, billing_entity:, invoice_custom_section: section)
    end

    it "serializes only the requested relationships" do
      expect(payload[:taxes]).to eq([{
        lago_id: tax.id,
        name: tax.name,
        code: tax.code,
        rate: tax.rate,
        description: tax.description,
        created_at: tax.created_at.iso8601,
        updated_at: tax.updated_at.iso8601,
        deleted_at: nil
      }])
      expect(payload[:selected_invoice_custom_sections]).to eq([{
        lago_id: section.id,
        code: section.code,
        name: section.name,
        description: section.description,
        details: section.details,
        display_name: section.display_name,
        created_at: section.created_at.iso8601,
        updated_at: section.updated_at.iso8601,
        deleted_at: nil
      }])
    end
  end

  context "with a deleted entity" do
    let(:billing_entity) { create(:billing_entity, :deleted, organization:) }

    it "includes the deletion timestamp" do
      expect(payload[:deleted_at]).to eq(billing_entity.deleted_at.iso8601)
    end
  end
end

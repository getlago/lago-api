# frozen_string_literal: true

class PopulateBillingEntityForOrganizations < ActiveRecord::Migration[7.1]
  class Organization < ApplicationRecord
    has_one :applied_dunning_campaign, -> { where(applied_to_organization: true) }, class_name: "DunningCampaign"
    has_many :invoice_custom_section_selections
    has_many :customers
    has_many :customers
    has_many :invoices
    has_many :daily_usages
    has_many :integrations, class_name: "Integrations::BaseIntegration"
    has_many :payment_providers, class_name: "PaymentProviders::BaseProvider"
    has_many :payment_requests
    has_many :cached_aggregations
    has_many :data_exports
    has_many :taxes
  end

  def change
    Organization.find_each do |organization|
      billing_entity = BillingEntity.create(
        organization_id: organization.id,
        address_line1: organization.address_line1,
        address_line2: organization.address_line2,
        city: organization.city,
        country: organization.country,
        zipcode: organization.zipcode,
        state: organization.state,
        timezone: organization.timezone,

        # currency and locale
        default_currency: organization.default_currency,
        document_locale: organization.document_locale,

        # invoice settings
        document_number_prefix: organization.document_number_prefix,
        document_numbering: organization.document_numbering,
        finalize_zero_amount_invoice: organization.finalize_zero_amount_invoice,
        invoice_footer: organization.invoice_footer,
        invoice_grace_period: organization.invoice_grace_period,

        # entity settings
        email: organization.email,
        email_settings: organization.email_settings,
        eu_tax_management: organization.eu_tax_management,
        legal_name: organization.legal_name,
        legal_number: organization.legal_number,
        logo: organization.logo,
        name: organization.name,
        tax_identification_number: organization.tax_identification_number,
        vat_rate: organization.vat_rate,
        applied_dunning_campaign_id: organization.applied_dunning_campaign&.id
      )
      billing_entity.save!

      # rubocop:disable Rails/SkipsModelValidations
      organization.customers.update_all(billing_entity_id: billing_entity.id)
      organization.invoices.update_all(billing_entity_id: billing_entity.id)
      organization.daily_usages.update_all(billing_entity_id: billing_entity.id)
      organization.integrations.update_all(billing_entity_id: billing_entity.id)
      organization.payment_providers.update_all(billing_entity_id: billing_entity.id)
      organization.payment_requests.update_all(billing_entity_id: billing_entity.id)
      organization.cached_aggregations.update_all(billing_entity_id: billing_entity.id)
      organization.data_exports.update_all(billing_entity_id: billing_entity.id)
      organization.invoice_custom_section_selections.update_all(billing_entity_id: billing_entity.id)
      ErrorDetail.where(organization_id: organization.id).update_all(billing_entity_id: billing_entity.id)
      # rubocop:enable Rails/SkipsModelValidations

      organization.taxes.applied_to_organization.each do |tax|
        billing_entity.taxes << tax
      end
    end
  end
end

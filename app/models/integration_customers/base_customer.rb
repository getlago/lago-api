# frozen_string_literal: true

module IntegrationCustomers
  class BaseCustomer < ApplicationRecord
    include PaperTrailTraceable
    include SettingsStorable

    self.table_name = "integration_customers"

    belongs_to :customer
    belongs_to :integration, class_name: "Integrations::BaseIntegration"
    belongs_to :organization

    TAX_INTEGRATION_TYPES = %w[
      IntegrationCustomers::AnrokCustomer
      IntegrationCustomers::AvalaraCustomer
    ].freeze

    CATEGORIES = {
      payment: "payment",
      tax: "tax",
      accounting: "accounting",
      crm: "crm"
    }.freeze

    CATEGORY_BY_TYPE = {
      "IntegrationCustomers::AnrokCustomer" => CATEGORIES[:tax],
      "IntegrationCustomers::AvalaraCustomer" => CATEGORIES[:tax],
      "IntegrationCustomers::NetsuiteCustomer" => CATEGORIES[:accounting],
      "IntegrationCustomers::XeroCustomer" => CATEGORIES[:accounting],
      "IntegrationCustomers::HubspotCustomer" => CATEGORIES[:crm],
      "IntegrationCustomers::SalesforceCustomer" => CATEGORIES[:crm]
    }.freeze

    enum :category, CATEGORIES, validate: {allow_nil: true}

    before_validation :set_category
    before_validation :set_code

    validates :customer_id, uniqueness: {scope: :type}
    validates :code, uniqueness: {scope: %i[customer_id category]}, allow_nil: true
    validate :only_one_tax_integration_per_customer, if: :tax_kind?

    scope :accounting_kind, -> do
      where(type: %w[IntegrationCustomers::NetsuiteCustomer IntegrationCustomers::XeroCustomer])
    end

    scope :tax_kind, -> do
      where(type: TAX_INTEGRATION_TYPES)
    end

    scope :hubspot_kind, -> do
      where(type: %w[IntegrationCustomers::HubspotCustomer])
    end

    scope :salesforce_kind, -> do
      where(type: %w[IntegrationCustomers::SalesforceCustomer])
    end

    settings_accessors :sync_with_provider

    def self.customer_type(type)
      case type
      when "netsuite"
        "IntegrationCustomers::NetsuiteCustomer"
      when "okta"
        "IntegrationCustomers::OktaCustomer"
      when "anrok"
        "IntegrationCustomers::AnrokCustomer"
      when "avalara"
        "IntegrationCustomers::AvalaraCustomer"
      when "xero"
        "IntegrationCustomers::XeroCustomer"
      when "hubspot"
        "IntegrationCustomers::HubspotCustomer"
      when "salesforce"
        "IntegrationCustomers::SalesforceCustomer"
      else
        raise(NotImplementedError)
      end
    end

    def self.category_for(customer_type)
      CATEGORY_BY_TYPE[customer_type]
    end

    def tax_kind?
      TAX_INTEGRATION_TYPES.include?(type)
    end

    private

    def set_category
      self.category ||= self.class.category_for(type)
    end

    def set_code
      self.code ||= integration&.code
    end

    def only_one_tax_integration_per_customer
      conflict = IntegrationCustomers::BaseCustomer.tax_kind.where(customer_id:)
      conflict = conflict.where.not(id:) if persisted?

      return unless conflict.exists?

      errors.add(:type, "tax_integration_exists")
    end
  end
end

# == Schema Information
#
# Table name: integration_customers
# Database name: primary
#
#  id                   :uuid             not null, primary key
#  category             :enum
#  code                 :string
#  is_default           :boolean          default(FALSE), not null
#  settings             :jsonb            not null
#  type                 :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  customer_id          :uuid             not null
#  external_customer_id :string
#  integration_id       :uuid             not null
#  organization_id      :uuid             not null
#
# Indexes
#
#  index_integration_customers_on_customer_category_code     (customer_id,category,code) UNIQUE
#  index_integration_customers_on_customer_category_default  (customer_id,category) UNIQUE WHERE is_default
#  index_integration_customers_on_customer_id                (customer_id)
#  index_integration_customers_on_customer_id_and_type       (customer_id,type) UNIQUE
#  index_integration_customers_on_external_customer_id       (external_customer_id)
#  index_integration_customers_on_integration_id             (integration_id)
#  index_integration_customers_on_organization_id            (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (integration_id => integrations.id)
#  fk_rails_...  (organization_id => organizations.id)
#

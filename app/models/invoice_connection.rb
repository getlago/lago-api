# frozen_string_literal: true

class InvoiceConnection < ApplicationRecord
  CATEGORIES = {
    payment: "payment",
    tax: "tax",
    accounting: "accounting",
    crm: "crm"
  }.freeze

  belongs_to :organization
  belongs_to :invoice
  belongs_to :payment_provider_customer,
    optional: true,
    class_name: "PaymentProviderCustomers::BaseCustomer"
  belongs_to :integration_customer,
    optional: true,
    class_name: "IntegrationCustomers::BaseCustomer"

  enum :category, CATEGORIES, validate: true
end

# == Schema Information
#
# Table name: invoice_connections
# Database name: primary
#
#  id                           :uuid             not null, primary key
#  category                     :enum             not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  integration_customer_id      :uuid
#  invoice_id                   :uuid             not null
#  organization_id              :uuid             not null
#  payment_provider_customer_id :uuid
#
# Indexes
#
#  index_invoice_connections_on_integration_customer_id       (integration_customer_id)
#  index_invoice_connections_on_invoice_id_and_category       (invoice_id,category) UNIQUE
#  index_invoice_connections_on_organization_id               (organization_id)
#  index_invoice_connections_on_payment_provider_customer_id  (payment_provider_customer_id)
#
# Foreign Keys
#
#  fk_rails_...  (integration_customer_id => integration_customers.id)
#  fk_rails_...  (invoice_id => invoices.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (payment_provider_customer_id => payment_provider_customers.id)
#

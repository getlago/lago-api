# frozen_string_literal: true

class BillingObjectConnection < ApplicationRecord
  CATEGORIES = {
    payment: "payment",
    tax: "tax",
    accounting: "accounting",
    crm: "crm"
  }.freeze

  BEHAVIORS = {
    specific: "specific",
    skip: "skip"
  }.freeze

  belongs_to :organization
  belongs_to :owner, polymorphic: true
  belongs_to :payment_provider_customer, class_name: "PaymentProviderCustomers::BaseCustomer", optional: true
  belongs_to :integration_customer, class_name: "IntegrationCustomers::BaseCustomer", optional: true

  enum :category, CATEGORIES, validate: true
  enum :behavior, BEHAVIORS, validate: true
end

# == Schema Information
#
# Table name: billing_object_connections
# Database name: primary
#
#  id                           :uuid             not null, primary key
#  behavior                     :enum             not null
#  category                     :enum             not null
#  owner_type                   :string           not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  integration_customer_id      :uuid
#  organization_id              :uuid             not null
#  owner_id                     :uuid             not null
#  payment_provider_customer_id :uuid
#
# Indexes
#
#  idx_on_owner_type_owner_id_category_937f7f9880               (owner_type,owner_id,category) UNIQUE
#  idx_on_payment_provider_customer_id_ed5e6793bd               (payment_provider_customer_id)
#  index_billing_object_connections_on_integration_customer_id  (integration_customer_id)
#  index_billing_object_connections_on_organization_id          (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (integration_customer_id => integration_customers.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (payment_provider_customer_id => payment_provider_customers.id)
#

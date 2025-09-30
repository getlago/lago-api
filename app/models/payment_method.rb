# frozen_string_literal: true

class PaymentMethod < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :organization
  belongs_to :customer
  belongs_to :payment_provider_customer, class_name: "PaymentProviderCustomers::BaseCustomer"
end

# == Schema Information
#
# Table name: payment_methods
#
#  id                           :uuid             not null, primary key
#  details                      :jsonb            not null
#  is_default                   :boolean          default(FALSE), not null
#  method_type                  :string
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  customer_id                  :uuid             not null
#  organization_id              :uuid             not null
#  payment_provider_customer_id :uuid             not null
#  provider_method_id           :string
#
# Indexes
#
#  index_payment_methods_on_customer_id                   (customer_id)
#  index_payment_methods_on_method_type                   (method_type)
#  index_payment_methods_on_organization_id               (organization_id)
#  index_payment_methods_on_payment_provider_customer_id  (payment_provider_customer_id)
#  unique_default_payment_method_per_customer             (customer_id) UNIQUE WHERE (is_default = true)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (payment_provider_customer_id => payment_provider_customers.id)
#

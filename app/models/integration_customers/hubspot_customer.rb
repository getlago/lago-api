# frozen_string_literal: true

module IntegrationCustomers
  class HubspotCustomer < BaseCustomer
    settings_accessors :targeted_object, :email

    def object_type
      if targeted_object == 'contacts'
        'contact'
      else
        'company'
      end
    end
  end
end

# == Schema Information
#
# Table name: integration_customers
#
#  id                   :uuid             not null, primary key
#  settings             :jsonb            not null
#  type                 :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  customer_id          :uuid             not null
#  external_customer_id :string
#  integration_id       :uuid             not null
#
# Indexes
#
#  index_integration_customers_on_customer_id           (customer_id)
#  index_integration_customers_on_customer_id_and_type  (customer_id,type) UNIQUE
#  index_integration_customers_on_external_customer_id  (external_customer_id)
#  index_integration_customers_on_integration_id        (integration_id)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (integration_id => integrations.id)
#

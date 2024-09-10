# frozen_string_literal: true

module Integrations
  module Aggregator
    module Contacts
      module Payloads
        class BasePayload < Integrations::Aggregator::BasePayload
          def initialize(integration:, customer:, integration_customer: nil, subsidiary_id: nil)
            super(integration:)

            @customer = customer
            @integration_customer = integration_customer
            @subsidiary_id = subsidiary_id
          end

          def create_body
            [
              {
                'name' => customer.name,
                'firstname' => customer.firstname,
                'lastname' => customer.lastname,
                'city' => customer.city,
                'zip' => customer.zipcode,
                'country' => customer.country,
                'state' => customer.state,
                'email' => email,
                'phone' => phone
              }
            ]
          end

          def update_body
            [
              {
                'id' => integration_customer.external_customer_id,
                'name' => customer.name,
                'firstname' => customer.firstname,
                'lastname' => customer.lastname,
                'city' => customer.city,
                'zip' => customer.zipcode,
                'country' => customer.country,
                'state' => customer.state,
                'email' => email,
                'phone' => phone
              }
            ]
          end

          private

          attr_reader :customer, :integration_customer, :subsidiary_id

          def email
            customer.email.to_s.split(',').first&.strip
          end

          def phone
            customer.phone.to_s.split(',').first&.strip
          end
        end
      end
    end
  end
end

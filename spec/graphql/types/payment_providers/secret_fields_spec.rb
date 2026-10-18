# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Payment provider secret fields" do # rubocop:disable RSpec/DescribeClass
  # A field whose name looks like a credential must be masked, or only readable by roles that can
  # configure the integration.
  configure_permissions = %w[organization:integrations:create organization:integrations:update]

  provider_types = [
    Types::PaymentProviders::Adyen,
    Types::PaymentProviders::Cashfree,
    Types::PaymentProviders::Flutterwave,
    Types::PaymentProviders::Gocardless,
    Types::PaymentProviders::Moneyhash,
    Types::PaymentProviders::Stripe
  ]

  provider_types.each do |type|
    type.fields.each_value do |field|
      next unless field.name.match?(/secret|key|token/i)
      next if field.type.unwrap == GraphQL::Types::Boolean

      it "protects #{type.graphql_name}.#{field.name}" do
        masked = field.type.unwrap == Types::ObfuscatedStringType
        restricted = field.permissions.present? && (field.permissions - configure_permissions).empty?

        expect(masked || restricted).to be(true)
      end
    end
  end
end

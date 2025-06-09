# frozen_string_literal: true

FactoryBot.define do
  factory :netsuite_mapping, class: "IntegrationMappings::NetsuiteMapping" do
    association :integration, factory: :netsuite_integration
    association :mappable, factory: :add_on
    organization { integration&.organization || association(:organization) }

    settings do
      {
        external_id: "netsuite-123",
        external_account_code: "netsuite-code-1",
        external_name: "Credits and Discounts"
      }
    end
  end

  factory :xero_mapping, class: "IntegrationMappings::XeroMapping" do
    association :integration, factory: :xero_integration
    association :mappable, factory: :add_on
    organization { integration&.organization || association(:organization) }

    settings do
      {
        external_id: "xero-123",
        external_account_code: "xero-code-1",
        external_name: "Credits and Discounts"
      }
    end
  end
end

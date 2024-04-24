# frozen_string_literal: true

FactoryBot.define do
  factory :netsuite_mapping, class: 'IntegrationMappings::NetsuiteMapping' do
    association :integration, factory: :netsuite_integration
    association :mappable, factory: :add_on

    settings do
      {
        external_id: 'netsuite-123',
        external_account_code: 'netsuite-code-1',
        external_name: 'Credits and Discounts',
      }
    end
  end
end

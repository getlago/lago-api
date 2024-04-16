# frozen_string_literal: true

FactoryBot.define do
  factory :netsuite_mapping, class: 'IntegrationMappings::NetsuiteMapping' do
    association :integration, factory: :netsuite_integration
    association :mappable, factory: :add_on

    settings do
      {
        netsuite_id: 'netsuite-123',
        netsuite_account_code: 'netsuite-code-1',
        netsuite_name: 'Credits and Discounts',
      }
    end
  end
end

class IntegrationResource < ApplicationRecord
  belongs_to :syncable, polymorphic: true
  belongs_to :integration, class_name: 'Integrations::BaseIntegration'
end

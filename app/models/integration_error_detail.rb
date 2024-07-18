class IntegrationErrorDetail < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :integration, class_name: 'Integrations::BaseIntegration'
  belongs_to :owner, polymorphic: true
end

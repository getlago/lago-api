# frozen_string_literal: true

module IntegrationMappable
  extend ActiveSupport::Concern

  included do
    has_many :integration_mappings, as: :mappable, class_name: 'Integrations::BaseMapping', dependent: :destroy
    has_many :netsuite_mappings, as: :mappable, class_name: 'Integrations::NetsuiteMapping', dependent: :destroy
  end
end

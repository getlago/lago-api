# frozen_string_literal: true

module Integrations
  class SalesforceIntegration < BaseIntegration
    validates :name, :code, :instance_id, presence: true

    settings_accessors :name, :code, :instance_id
  end
end

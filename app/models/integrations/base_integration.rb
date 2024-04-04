# frozen_string_literal: true

module Integrations
  class BaseIntegration < ApplicationRecord
    include PaperTrailTraceable
    include SecretsStorable
    include SettingsStorable

    self.table_name = 'integrations'

    belongs_to :organization

    validates :code, uniqueness: { scope: :organization_id }
    validates :name, presence: true
  end
end

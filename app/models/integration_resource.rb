class IntegrationResource < ApplicationRecord
  belongs_to :syncable, polymorphic: true
end

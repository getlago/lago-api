class PublisherPortalRecord < ApplicationRecord
  self.abstract_class = true

  connects_to database: { writing: :authentication, reading: :authentication }
end

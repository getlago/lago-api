# frozen_string_literal: true

class PublisherPortalRecord < ApplicationRecord
  self.abstract_class = true

  connects_to database: { writing: :publisher_portal, reading: :publisher_portal }
end
